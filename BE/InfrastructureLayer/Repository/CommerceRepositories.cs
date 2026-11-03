using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using DomainLayer.Constants;
using DomainLayer.Entities;
using DomainLayer.Interfaces;
using InfrastructureLayer.Database;
using MongoDB.Bson;
using MongoDB.Driver;

namespace InfrastructureLayer.Repository
{
    public class BookingRepository : IBookingRepository
    {
        private static readonly FilterDefinitionBuilder<ChefBooking> F = Builders<ChefBooking>.Filter;
        private static readonly ProjectionDefinition<ChefBooking> WithoutMessages = Builders<ChefBooking>.Projection.Exclude(b => b.Messages);
        private readonly IMongoCollection<ChefBooking> _col;

        public BookingRepository(MongoDbContext context)
        {
            _col = context.Bookings;
        }

        public Task InsertAsync(ChefBooking booking) => _col.InsertOneAsync(booking);

        public async Task<ChefBooking?> GetAsync(string id)
        {
            if (!ObjectId.TryParse(id, out _)) return null;
            return await _col.Find(F.Eq(b => b.Id, id) & F.Eq(b => b.IsDeleted, false)).FirstOrDefaultAsync();
        }

        public Task<ChefBooking?> FindByOrderIdAsync(string orderId) =>
            FindOne(F.Eq(b => b.Order!.Id, orderId));

        public Task<ChefBooking?> FindByPaymentIdAsync(string paymentId) =>
            FindOne(F.ElemMatch(b => b.Order!.Payments, p => p.Id == paymentId));

        public Task<ChefBooking?> FindByEscrowIdAsync(string escrowId) =>
            FindOne(F.Eq(b => b.Escrow!.Id, escrowId));

        public Task<ChefBooking?> FindByComplaintIdAsync(string complaintId) =>
            FindOne(F.Eq(b => b.Complaint!.Id, complaintId));

        private async Task<ChefBooking?> FindOne(FilterDefinition<ChefBooking> filter) =>
            await _col.Find(filter & F.Eq(b => b.IsDeleted, false)).FirstOrDefaultAsync();

        public async Task<bool> TryReplaceAsync(ChefBooking booking)
        {
            var expected = booking.Version;
            booking.Version = expected + 1;
            var result = await _col.ReplaceOneAsync(F.Eq(b => b.Id, booking.Id) & F.Eq(b => b.Version, expected), booking);
            if (result.MatchedCount == 1) return true;
            booking.Version = expected;
            return false;
        }

        public Task RemoveOutboxEntryAsync(string bookingId, string key) =>
            _col.UpdateOneAsync(
                F.Eq(b => b.Id, bookingId),
                Builders<ChefBooking>.Update
                    .PullFilter(b => b.Outbox, i => i.Key == key)
                    .Inc(b => b.Version, 1));

        public Task<List<ChefBooking>> ListForMemberAsync(string memberId) =>
            List(F.Eq(b => b.MemberId, memberId) & F.Eq(b => b.IsDeleted, false));

        public Task<List<ChefBooking>> ListForChefAsync(string chefId) =>
            List(F.Eq(b => b.ChefId, chefId) & F.Eq(b => b.IsDeleted, false));

        public Task<List<ChefBooking>> ListWithEscrowAsync(string? chefId = null)
        {
            var filter = F.Ne(b => b.Escrow, null) & F.Eq(b => b.IsDeleted, false);
            if (chefId != null) filter &= F.Eq(b => b.ChefId, chefId);
            return List(filter);
        }

        public Task<List<ChefBooking>> ListWithComplaintAsync() =>
            List(F.Ne(b => b.Complaint, null) & F.Eq(b => b.IsDeleted, false));

        public Task<List<ChefBooking>> ListWithOrderAsync() =>
            List(F.Ne(b => b.Order, null) & F.Eq(b => b.IsDeleted, false));

        private Task<List<ChefBooking>> List(FilterDefinition<ChefBooking> filter) =>
            _col.Find(filter)
                .Project<ChefBooking>(WithoutMessages)
                .SortByDescending(b => b.UpdatedAt)
                .ToListAsync();

        public async Task<List<string>> ListDueIdsAsync(DateTime now, string? userId = null)
        {
            var due = F.Or(
                F.Eq(b => b.Status, BookingStatuses.AwaitingPayment) & F.Lt(b => b.Contract!.PaymentDueAt, now),
                F.Eq(b => b.Escrow!.Status, EscrowStatuses.Held) & F.Eq(b => b.Escrow!.CompletedAt, null) & F.Lte(b => b.Escrow!.AutoCompleteAt, now),
                F.Eq(b => b.Escrow!.Status, EscrowStatuses.Held) & F.Lte(b => b.Escrow!.ReleaseAt, now));
            return await IdsAsync(due, userId);
        }

        public Task<List<string>> ListIdsWithOutboxAsync(string? userId = null) =>
            IdsAsync(F.SizeGt(b => b.Outbox, 0), userId);

        private async Task<List<string>> IdsAsync(FilterDefinition<ChefBooking> filter, string? userId)
        {
            if (userId != null) filter &= F.Or(F.Eq(b => b.MemberId, userId), F.Eq(b => b.ChefId, userId));
            var rows = await _col.Find(filter & F.Eq(b => b.IsDeleted, false)).Project(b => b.Id).ToListAsync();
            return rows;
        }
    }

    public class WalletRepository : IWalletRepository
    {
        private static readonly FilterDefinitionBuilder<Wallet> F = Builders<Wallet>.Filter;
        private readonly IMongoCollection<Wallet> _col;

        public WalletRepository(MongoDbContext context)
        {
            _col = context.Wallets;
        }

        public async Task<Wallet?> GetAsync(string userId)
        {
            if (!ObjectId.TryParse(userId, out _)) return null;
            return await _col.Find(F.Eq(w => w.Id, userId)).FirstOrDefaultAsync();
        }

        public async Task EnsureAsync(string userId, DateTime now)
        {
            try
            {
                await _col.UpdateOneAsync(
                    F.Eq(w => w.Id, userId),
                    Builders<Wallet>.Update
                        .SetOnInsert(w => w.CreatedAt, now)
                        .SetOnInsert(w => w.IsDeleted, false)
                        .SetOnInsert(w => w.Available, 0)
                        .SetOnInsert(w => w.Processing, 0)
                        .SetOnInsert(w => w.Withdrawn, 0)
                        .SetOnInsert(w => w.AppliedEntryIds, new List<string>()),
                    new UpdateOptions { IsUpsert = true });
            }
            catch (MongoWriteException ex) when (ex.WriteError?.Category == ServerErrorCategory.DuplicateKey)
            {
                // Hai yêu cầu cùng tạo ví: một bên thắng là đủ.
            }
        }

        public async Task<WalletApplyResult> TryApplyAsync(WalletLedgerEntry entry, DateTime now)
        {
            var filter = F.Eq(w => w.Id, entry.UserId) & F.Ne("AppliedEntryIds", entry.Id);
            if (entry.DeltaAvailable < 0) filter &= F.Gte(w => w.Available, -entry.DeltaAvailable);
            if (entry.DeltaProcessing < 0) filter &= F.Gte(w => w.Processing, -entry.DeltaProcessing);

            var result = await _col.UpdateOneAsync(
                filter,
                Builders<Wallet>.Update
                    .Inc(w => w.Available, entry.DeltaAvailable)
                    .Inc(w => w.Processing, entry.DeltaProcessing)
                    .Inc(w => w.Withdrawn, entry.DeltaWithdrawn)
                    .Push(w => w.AppliedEntryIds, entry.Id)
                    .Set(w => w.UpdatedAt, now));
            if (result.MatchedCount == 1) return WalletApplyResult.Applied;
            return await ContainsEntryAsync(entry.UserId, entry.Id) ? WalletApplyResult.AlreadyApplied : WalletApplyResult.Insufficient;
        }

        public async Task<bool> ContainsEntryAsync(string userId, string entryId)
        {
            if (!ObjectId.TryParse(userId, out _)) return false;
            return await _col.Find(F.Eq(w => w.Id, userId) & F.AnyEq(w => w.AppliedEntryIds, entryId)).AnyAsync();
        }

        public async Task SaveBankAccountAsync(string userId, WalletBankAccount account, DateTime now)
        {
            await EnsureAsync(userId, now);
            await _col.UpdateOneAsync(
                F.Eq(w => w.Id, userId),
                Builders<Wallet>.Update.Set(w => w.BankAccount, account).Set(w => w.UpdatedAt, now));
        }

        public Task<List<Wallet>> ListAsync() => _col.Find(F.Empty).ToListAsync();
    }

    public class WalletLedgerRepository : IWalletLedgerRepository
    {
        private static readonly FilterDefinitionBuilder<WalletLedgerEntry> F = Builders<WalletLedgerEntry>.Filter;
        private readonly IMongoCollection<WalletLedgerEntry> _col;

        public WalletLedgerRepository(MongoDbContext context)
        {
            _col = context.WalletLedger;
        }

        public async Task<bool> TryInsertAsync(WalletLedgerEntry entry)
        {
            try
            {
                await _col.InsertOneAsync(entry);
                return true;
            }
            catch (MongoWriteException ex) when (ex.WriteError?.Category == ServerErrorCategory.DuplicateKey)
            {
                return false;
            }
        }

        public async Task<WalletLedgerEntry?> GetAsync(string id) =>
            await _col.Find(F.Eq(e => e.Id, id)).FirstOrDefaultAsync();

        public Task MarkAppliedAsync(string id) =>
            _col.UpdateOneAsync(F.Eq(e => e.Id, id), Builders<WalletLedgerEntry>.Update.Set(e => e.Applied, true).Set(e => e.Voided, false));

        public Task VoidAsync(string id) =>
            _col.UpdateOneAsync(F.Eq(e => e.Id, id) & F.Eq(e => e.Applied, false), Builders<WalletLedgerEntry>.Update.Set(e => e.Voided, true));

        public Task ReviveAsync(string id) =>
            _col.UpdateOneAsync(F.Eq(e => e.Id, id) & F.Eq(e => e.Voided, true), Builders<WalletLedgerEntry>.Update.Set(e => e.Voided, false));

        public Task MarkSagaDoneAsync(string id) =>
            _col.UpdateOneAsync(F.Eq(e => e.Id, id), Builders<WalletLedgerEntry>.Update.Set(e => e.SagaDone, true));

        public Task<List<WalletLedgerEntry>> ListUnappliedAsync(string? userId = null)
        {
            var filter = F.Eq(e => e.Applied, false) & F.Eq(e => e.Voided, false);
            if (userId != null) filter &= F.Eq(e => e.UserId, userId);
            return _col.Find(filter).ToListAsync();
        }

        public Task<List<WalletLedgerEntry>> ListOpenWalletPaymentsAsync(string? userId = null)
        {
            var filter = F.Eq(e => e.Kind, LedgerKinds.WalletPayment) & F.Eq(e => e.Applied, true) & F.Eq(e => e.SagaDone, false);
            if (userId != null) filter &= F.Eq(e => e.UserId, userId);
            return _col.Find(filter).ToListAsync();
        }

        public Task<List<WalletLedgerEntry>> ListForUserAsync(string userId) =>
            _col.Find(F.Eq(e => e.UserId, userId) & F.Eq(e => e.Voided, false)).SortByDescending(e => e.OccurredAt).ToListAsync();

        public Task<List<WalletLedgerEntry>> ListByTypesAsync(params string[] types) =>
            _col.Find(F.In(e => e.Type, types) & F.Eq(e => e.Voided, false)).ToListAsync();
    }

    public class WithdrawalRepository : IWithdrawalRepository
    {
        private static readonly FilterDefinitionBuilder<WithdrawalRequest> F = Builders<WithdrawalRequest>.Filter;
        private readonly IMongoCollection<WithdrawalRequest> _col;

        public WithdrawalRepository(MongoDbContext context)
        {
            _col = context.Withdrawals;
        }

        public async Task<bool> TryInsertAsync(WithdrawalRequest request)
        {
            try
            {
                await _col.InsertOneAsync(request);
                return true;
            }
            catch (MongoWriteException ex) when (ex.WriteError?.Category == ServerErrorCategory.DuplicateKey)
            {
                return false;
            }
        }

        public async Task<WithdrawalRequest?> GetAsync(string id)
        {
            if (!ObjectId.TryParse(id, out _)) return null;
            return await _col.Find(F.Eq(w => w.Id, id) & F.Eq(w => w.IsDeleted, false) & F.Eq(w => w.Funded, true)).FirstOrDefaultAsync();
        }

        public async Task<WithdrawalRequest?> FindByDedupeKeyAsync(string key) =>
            await _col.Find(F.Eq(w => w.DedupeKey, key) & F.Eq(w => w.IsDeleted, false)).FirstOrDefaultAsync();

        public async Task<WithdrawalRequest?> FindRecentAsync(string userId, long amount, DateTime since) =>
            await _col.Find(F.Eq(w => w.UserId, userId) & F.Eq(w => w.Amount, amount) & F.Gte(w => w.CreatedAt, since)
                    & F.Eq(w => w.Status, WithdrawalStatuses.Processing) & F.Eq(w => w.IsDeleted, false))
                .SortByDescending(w => w.CreatedAt).FirstOrDefaultAsync();

        /// <summary>Tiền đã giữ thì yêu cầu phải tồn tại, kể cả khi job vừa bỏ nó vì tưởng yêu cầu đã chết.</summary>
        public Task MarkFundedAsync(string id) =>
            _col.UpdateOneAsync(F.Eq(w => w.Id, id), Builders<WithdrawalRequest>.Update.Set(w => w.Funded, true).Set(w => w.IsDeleted, false).Unset(w => w.DeletedAt));

        public Task DiscardAsync(string id, DateTime now) =>
            _col.UpdateOneAsync(
                F.Eq(w => w.Id, id) & F.Eq(w => w.Funded, false),
                Builders<WithdrawalRequest>.Update.Set(w => w.IsDeleted, true).Set(w => w.DeletedAt, now).Unset(w => w.DedupeKey));

        public async Task<WithdrawalRequest?> TryDecideAsync(string id, string status, string actor, DateTime now, string? transactionRef, string? reason)
        {
            var filter = F.Eq(w => w.Id, id) & F.Eq(w => w.Status, WithdrawalStatuses.Processing) & F.Eq(w => w.Funded, true) & F.Eq(w => w.IsDeleted, false);
            var update = Builders<WithdrawalRequest>.Update
                .Set(w => w.Status, status)
                .Set(w => w.ProcessedAt, now)
                .Set(w => w.ProcessedBy, actor)
                .Set(w => w.TransactionRef, transactionRef)
                .Set(w => w.Reason, reason)
                .Set(w => w.Posted, false)
                .Set(w => w.UpdatedAt, now)
                .Unset(w => w.DedupeKey);
            return await _col.FindOneAndUpdateAsync(filter, update, new FindOneAndUpdateOptions<WithdrawalRequest> { ReturnDocument = ReturnDocument.After });
        }

        public Task MarkPostedAsync(string id) =>
            _col.UpdateOneAsync(F.Eq(w => w.Id, id), Builders<WithdrawalRequest>.Update.Set(w => w.Posted, true));

        public Task<List<WithdrawalRequest>> ListUnfundedAsync(DateTime createdBefore, string? userId = null)
        {
            var filter = F.Eq(w => w.Funded, false) & F.Eq(w => w.IsDeleted, false) & F.Lte(w => w.CreatedAt, createdBefore);
            if (userId != null) filter &= F.Eq(w => w.UserId, userId);
            return _col.Find(filter).ToListAsync();
        }

        public Task<List<WithdrawalRequest>> ListUnpostedAsync(string? userId = null)
        {
            var filter = F.Ne(w => w.Status, WithdrawalStatuses.Processing) & F.Eq(w => w.Posted, false) & F.Eq(w => w.IsDeleted, false);
            if (userId != null) filter &= F.Eq(w => w.UserId, userId);
            return _col.Find(filter).ToListAsync();
        }

        public Task<List<WithdrawalRequest>> ListForUserAsync(string userId) =>
            _col.Find(F.Eq(w => w.UserId, userId) & F.Eq(w => w.Funded, true) & F.Eq(w => w.IsDeleted, false))
                .SortByDescending(w => w.CreatedAt).ToListAsync();

        public Task<List<WithdrawalRequest>> ListAllAsync() =>
            _col.Find(F.Eq(w => w.Funded, true) & F.Eq(w => w.IsDeleted, false)).SortByDescending(w => w.CreatedAt).ToListAsync();
    }
}
