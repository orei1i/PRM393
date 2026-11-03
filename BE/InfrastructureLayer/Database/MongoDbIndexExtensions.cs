using System;
using System.Threading.Tasks;
using DomainLayer.Entities;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using MongoDB.Driver;

namespace InfrastructureLayer.Database
{
    public static class MongoDbIndexExtensions
    {
        public static async Task EnsureIndexesAsync(this IServiceProvider services)
        {
            using var scope = services.CreateScope();
            var context = scope.ServiceProvider.GetRequiredService<MongoDbContext>();
            var logger = scope.ServiceProvider.GetService<ILogger<MongoDbContext>>();

            // Chỉ mục duy nhất chặn ghi trùng (có cả tiền và lượt dùng thử): máy bận thì chờ thêm, đừng bỏ qua.
            const int pingAttempts = 5;
            for (var attempt = 1; ; attempt++)
            {
                try
                {
                    using var pingCts = new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(3));
                    await context.Database.RunCommandAsync((Command<MongoDB.Bson.BsonDocument>)"{ping:1}", cancellationToken: pingCts.Token);
                    break;
                }
                catch
                {
                    if (attempt < pingAttempts) continue;
                    logger?.LogCritical("MongoDB không phản hồi sau {Attempts} lần ping. Chưa tạo được chỉ mục, các chỉ mục duy nhất chưa có hiệu lực.", pingAttempts);
                    return;
                }
            }

            // Chat (DB chính) và kho tri thức (DB RAG riêng)
            await SafeCreateIndexAsync(async () =>
            {
                await context.ChatSessions.Indexes.CreateOneAsync(new CreateIndexModel<ChatSession>(
                    Builders<ChatSession>.IndexKeys.Ascending(s => s.OwnerKey).Ascending(s => s.ClientSessionId),
                    new CreateIndexOptions { Unique = true }));
                await context.ChatMessages.Indexes.CreateOneAsync(new CreateIndexModel<ChatMessage>(
                    Builders<ChatMessage>.IndexKeys.Ascending(m => m.SessionId).Ascending(m => m.CreatedAt)));
                await context.GuestTrials.Indexes.CreateOneAsync(new CreateIndexModel<GuestTrial>(
                    Builders<GuestTrial>.IndexKeys.Ascending(g => g.GuestKey),
                    new CreateIndexOptions { Unique = true }));
            }, "Chat", logger);

            var rag = scope.ServiceProvider.GetRequiredService<RagDbContext>();
            if (rag.IsConfigured)
            {
                await SafeCreateIndexAsync(async () =>
                {
                    await rag.Docs.Indexes.CreateOneAsync(new CreateIndexModel<KnowledgeDoc>(
                        Builders<KnowledgeDoc>.IndexKeys.Ascending(d => d.Status)));
                    await rag.Docs.Indexes.CreateOneAsync(new CreateIndexModel<KnowledgeDoc>(
                        Builders<KnowledgeDoc>.IndexKeys.Ascending(d => d.ContentHash)));
                    await rag.Chunks.Indexes.CreateOneAsync(new CreateIndexModel<KnowledgeChunk>(
                        Builders<KnowledgeChunk>.IndexKeys.Ascending(c => c.DocId).Ascending(c => c.ChunkIndex),
                        new CreateIndexOptions { Unique = true }));
                    await rag.Jobs.Indexes.CreateOneAsync(new CreateIndexModel<IngestionJob>(
                        Builders<IngestionJob>.IndexKeys.Ascending(j => j.DocId)));
                }, "Rag", logger);
            }

            // ─── BƯỚC 1: Chạy migrations trước khi tạo chỉ mục ──────────
            await RunSprintMigrationsAsync(context, logger);

            // ─── BƯỚC 2: Tạo từng chỉ mục trong try-catch độc lập ───────

            // 1. MediaAssets
            await SafeCreateIndexAsync(async () =>
            {
                var mediaPublicIdIndex = new CreateIndexModel<MediaAsset>(
                    Builders<MediaAsset>.IndexKeys.Ascending(m => m.PublicId),
                    new CreateIndexOptions { Unique = true, Sparse = true });
                var mediaOwnerIndex = new CreateIndexModel<MediaAsset>(
                    Builders<MediaAsset>.IndexKeys.Ascending(m => m.OwnerId).Descending(m => m.CreatedAt));
                await context.MediaAssets.Indexes.CreateManyAsync(new[] { mediaPublicIdIndex, mediaOwnerIndex });
            }, "MediaAssets (PublicId, OwnerId_CreatedAt)", logger);

            // 2. Posts
            await SafeCreateIndexAsync(async () =>
            {
                var postStatusIndex = new CreateIndexModel<Post>(
                    Builders<Post>.IndexKeys.Ascending(p => p.Status).Descending(p => p.CreatedAt));
                var postUserIndex = new CreateIndexModel<Post>(
                    Builders<Post>.IndexKeys.Ascending(p => p.UserId).Descending(p => p.CreatedAt));
                await context.Posts.Indexes.CreateManyAsync(new[] { postStatusIndex, postUserIndex });
            }, "Posts (Status_CreatedAt, UserId_CreatedAt)", logger);

            // 3. Comments (PostId + CreatedAt & ParentId + CreatedAt)
            await SafeCreateIndexAsync(async () =>
            {
                var commentPostIndex = new CreateIndexModel<Comment>(
                    Builders<Comment>.IndexKeys.Ascending(c => c.PostId).Descending(c => c.CreatedAt));
                var commentParentIndex = new CreateIndexModel<Comment>(
                    Builders<Comment>.IndexKeys.Ascending(c => c.ParentId).Ascending(c => c.CreatedAt));
                await context.Comments.Indexes.CreateManyAsync(new[] { commentPostIndex, commentParentIndex });
            }, "Comments (PostId_CreatedAt, ParentId_CreatedAt)", logger);

            // 4. PostLikes (Unique per user and post)
            await SafeCreateIndexAsync(async () =>
            {
                var likeIndex = new CreateIndexModel<PostLike>(
                    Builders<PostLike>.IndexKeys.Ascending(l => l.PostId).Ascending(l => l.UserId),
                    new CreateIndexOptions { Unique = true });
                await context.PostLikes.Indexes.CreateOneAsync(likeIndex);
            }, "PostLikes (PostId_UserId Unique)", logger);

            // 5. PostReports (Unique per user and post)
            await SafeCreateIndexAsync(async () =>
            {
                var reportIndex = new CreateIndexModel<PostReport>(
                    Builders<PostReport>.IndexKeys.Ascending(r => r.PostId).Ascending(r => r.UserId),
                    new CreateIndexOptions { Unique = true });
                await context.PostReports.Indexes.CreateOneAsync(reportIndex);
            }, "PostReports (PostId_UserId Unique)", logger);

            // 5b. Bài đã lưu, đánh giá và ghi chú công thức: mỗi người một dòng; phiên đăng nhập theo thiết bị
            await SafeCreateIndexAsync(async () =>
            {
                await context.Database.GetCollection<PostSave>("PostSaves").Indexes.CreateOneAsync(new CreateIndexModel<PostSave>(
                    Builders<PostSave>.IndexKeys.Ascending(x => x.PostId).Ascending(x => x.UserId),
                    new CreateIndexOptions { Unique = true }));
                await context.Database.GetCollection<RecipeReview>("RecipeReviews").Indexes.CreateOneAsync(new CreateIndexModel<RecipeReview>(
                    Builders<RecipeReview>.IndexKeys.Ascending(x => x.RecipeId).Ascending(x => x.UserId),
                    new CreateIndexOptions { Unique = true }));
                await context.Database.GetCollection<RecipeNote>("RecipeNotes").Indexes.CreateOneAsync(new CreateIndexModel<RecipeNote>(
                    Builders<RecipeNote>.IndexKeys.Ascending(x => x.RecipeId).Ascending(x => x.UserId),
                    new CreateIndexOptions { Unique = true }));
                await context.Users.Indexes.CreateOneAsync(new CreateIndexModel<User>(
                    Builders<User>.IndexKeys.Ascending("RefreshSessions.TokenHash")));
            }, "PostSaves, RecipeReviews, RecipeNotes, Users.RefreshSessions", logger);

            // 6. Users (Partial Unique on EmailNormalized & Sparse on RefreshTokenHash)
            await SafeCreateIndexAsync(async () =>
            {
                var userEmailIndex = new CreateIndexModel<User>(
                    Builders<User>.IndexKeys.Ascending(u => u.EmailNormalized),
                    new CreateIndexOptions<User>
                    {
                        Unique = true,
                        PartialFilterExpression = Builders<User>.Filter.And(
                            Builders<User>.Filter.Eq(u => u.IsDeleted, false),
                            Builders<User>.Filter.Type(u => u.EmailNormalized, MongoDB.Bson.BsonType.String)
                        )
                    });
                var userRefreshIndex = new CreateIndexModel<User>(
                    Builders<User>.IndexKeys.Ascending(u => u.RefreshTokenHash),
                    new CreateIndexOptions { Sparse = true });
                await context.Users.Indexes.CreateManyAsync(new[] { userEmailIndex, userRefreshIndex });
            }, "Users (EmailNormalized Partial Unique, RefreshTokenHash)", logger);

            // 7. HealthProfiles (Unique per user)
            await SafeCreateIndexAsync(async () =>
            {
                var healthProfileUserIndex = new CreateIndexModel<HealthProfile>(
                    Builders<HealthProfile>.IndexKeys.Ascending(h => h.UserId),
                    new CreateIndexOptions { Unique = true });
                await context.HealthProfiles.Indexes.CreateOneAsync(healthProfileUserIndex);
            }, "HealthProfiles (UserId Unique)", logger);

            // 8. HealthMetricLogs
            await SafeCreateIndexAsync(async () =>
            {
                var healthMetricIndex = new CreateIndexModel<HealthMetricLog>(
                    Builders<HealthMetricLog>.IndexKeys.Ascending(m => m.UserId).Descending(m => m.LoggedAt));
                await context.HealthMetricLogs.Indexes.CreateOneAsync(healthMetricIndex);
            }, "HealthMetricLogs (UserId_LoggedAt)", logger);

            // 9. Ingredients (Unique on NormalizedName)
            await SafeCreateIndexAsync(async () =>
            {
                var ingredientNameIndex = new CreateIndexModel<Ingredient>(
                    Builders<Ingredient>.IndexKeys.Ascending(i => i.NormalizedName),
                    new CreateIndexOptions { Unique = true });
                await context.Ingredients.Indexes.CreateOneAsync(ingredientNameIndex);
            }, "Ingredients (NormalizedName Unique)", logger);

            // 10. PantryItems: (UserId, NormalizedName Partial Unique) & (UserId, ExpiryDate)
            await SafeCreateIndexAsync(async () =>
            {
                var pantryUserNormalizedIndex = new CreateIndexModel<PantryItem>(
                    Builders<PantryItem>.IndexKeys.Ascending(p => p.UserId).Ascending(p => p.NormalizedName),
                    new CreateIndexOptions<PantryItem>
                    {
                        Unique = true,
                        PartialFilterExpression = Builders<PantryItem>.Filter.Eq(p => p.IsDeleted, false)
                    });
                var pantryUserExpiryIndex = new CreateIndexModel<PantryItem>(
                    Builders<PantryItem>.IndexKeys.Ascending(p => p.UserId).Ascending(p => p.ExpiryDate));
                await context.PantryItems.Indexes.CreateManyAsync(new[] { pantryUserNormalizedIndex, pantryUserExpiryIndex });
            }, "PantryItems (UserId_NormalizedName Unique, UserId_ExpiryDate)", logger);

            // 11. Recipes
            await SafeCreateIndexAsync(async () =>
            {
                var recipeFilterIndex = new CreateIndexModel<Recipe>(
                    Builders<Recipe>.IndexKeys.Ascending(r => r.IsVegan).Ascending(r => r.CreatedBy));
                await context.Recipes.Indexes.CreateOneAsync(recipeFilterIndex);
            }, "Recipes (IsVegan_CreatedBy)", logger);

            // 12. MealPlans (Partial Unique on UserId + StartDate where !IsDeleted)
            await SafeCreateIndexAsync(async () =>
            {
                var mealPlanUserWeekIndex = new CreateIndexModel<MealPlan>(
                    Builders<MealPlan>.IndexKeys.Ascending(m => m.UserId).Ascending(m => m.StartDate),
                    new CreateIndexOptions<MealPlan>
                    {
                        Unique = true,
                        PartialFilterExpression = Builders<MealPlan>.Filter.Eq(m => m.IsDeleted, false)
                    });
                await context.MealPlans.Indexes.CreateOneAsync(mealPlanUserWeekIndex);
            }, "MealPlans (UserId_StartDate Partial Unique)", logger);

            // 13. AiLogs
            await SafeCreateIndexAsync(async () =>
            {
                var aiLogTaskIndex = new CreateIndexModel<AiLog>(
                    Builders<AiLog>.IndexKeys.Ascending(a => a.TaskType).Descending(a => a.CreatedAt));
                var aiLogScanIndex = new CreateIndexModel<AiLog>(
                    Builders<AiLog>.IndexKeys.Ascending(a => a.ScanId),
                    new CreateIndexOptions { Sparse = true });
                await context.AiLogs.Indexes.CreateManyAsync(new[] { aiLogTaskIndex, aiLogScanIndex });
            }, "AiLogs (TaskType_CreatedAt, ScanId)", logger);

            // 14. Đặt chuyên gia, giữ tiền, ví, rút tiền
            await SafeCreateIndexAsync(async () =>
            {
                var b = Builders<ChefBooking>.IndexKeys;
                var hasOrderId = Builders<ChefBooking>.Filter.Type(x => x.Order!.Id, MongoDB.Bson.BsonType.String);
                var hasEscrowId = Builders<ChefBooking>.Filter.Type(x => x.Escrow!.Id, MongoDB.Bson.BsonType.String);
                await context.Bookings.Indexes.CreateManyAsync(new[]
                {
                    new CreateIndexModel<ChefBooking>(b.Ascending(x => x.MemberId).Descending(x => x.UpdatedAt)),
                    new CreateIndexModel<ChefBooking>(b.Ascending(x => x.ChefId).Descending(x => x.UpdatedAt)),
                    new CreateIndexModel<ChefBooking>(b.Ascending(x => x.Status).Ascending(x => x.Contract!.PaymentDueAt)),
                    new CreateIndexModel<ChefBooking>(b.Ascending(x => x.Escrow!.Status).Ascending(x => x.Escrow!.AutoCompleteAt)),
                    new CreateIndexModel<ChefBooking>(b.Ascending(x => x.Escrow!.Status).Ascending(x => x.Escrow!.ReleaseAt)),
                    new CreateIndexModel<ChefBooking>(b.Ascending(x => x.Order!.Id), new CreateIndexOptions<ChefBooking> { Unique = true, PartialFilterExpression = hasOrderId }),
                    new CreateIndexModel<ChefBooking>(b.Ascending(x => x.Escrow!.Id), new CreateIndexOptions<ChefBooking> { Unique = true, PartialFilterExpression = hasEscrowId }),
                    new CreateIndexModel<ChefBooking>(b.Ascending("Order.Payments._id"))
                });
            }, "ChefBookings", logger);

            await SafeCreateIndexAsync(async () =>
            {
                var l = Builders<WalletLedgerEntry>.IndexKeys;
                await context.WalletLedger.Indexes.CreateManyAsync(new[]
                {
                    new CreateIndexModel<WalletLedgerEntry>(l.Ascending(x => x.IdempotencyKey), new CreateIndexOptions { Unique = true }),
                    new CreateIndexModel<WalletLedgerEntry>(l.Ascending(x => x.UserId).Descending(x => x.OccurredAt)),
                    new CreateIndexModel<WalletLedgerEntry>(l.Ascending(x => x.Applied).Ascending(x => x.Voided))
                });
            }, "WalletLedger (IdempotencyKey Unique)", logger);

            await SafeCreateIndexAsync(async () =>
            {
                var w = Builders<WithdrawalRequest>.IndexKeys;
                await context.Withdrawals.Indexes.CreateManyAsync(new[]
                {
                    new CreateIndexModel<WithdrawalRequest>(w.Ascending(x => x.UserId).Descending(x => x.CreatedAt)),
                    new CreateIndexModel<WithdrawalRequest>(w.Ascending(x => x.Status).Ascending(x => x.CreatedAt)),
                    new CreateIndexModel<WithdrawalRequest>(w.Ascending(x => x.DedupeKey), new CreateIndexOptions { Unique = true, Sparse = true })
                });
            }, "WithdrawalRequests (DedupeKey Unique)", logger);

            await context.EnsureContentIndexesAsync(logger);

            logger?.LogInformation("Đã hoàn tất cấu hình tất cả chỉ mục MongoDB.");
        }

        private static async Task SafeCreateIndexAsync(Func<Task> action, string indexName, ILogger? logger)
        {
            try
            {
                await action();
            }
            catch (Exception ex)
            {
                logger?.LogWarning(ex, "Lỗi khi tạo chỉ mục {IndexName}. Tiếp tục tạo các chỉ mục khác.", indexName);
            }
        }

        public static async Task RunSprintMigrationsAsync(MongoDbContext context, ILogger? logger)
        {
            // A. Users Migration (Chuẩn hóa EmailNormalized, xử lý trùng lặp)
            try
            {
                var allUsers = await context.Users.Find(u => !u.IsDeleted).ToListAsync();
                var userGroups = allUsers
                    .Where(u => !string.IsNullOrWhiteSpace(u.Email))
                    .GroupBy(u => u.Email.Trim().ToLowerInvariant());

                foreach (var group in userGroups)
                {
                    var list = group.OrderBy(u => u.CreatedAt).ToList();
                    var oldest = list[0];

                    if (oldest.EmailNormalized != group.Key)
                    {
                        await context.Users.UpdateOneAsync(
                            Builders<User>.Filter.Eq(u => u.Id, oldest.Id),
                            Builders<User>.Update.Set(u => u.EmailNormalized, group.Key));
                    }

                    for (int i = 1; i < list.Count; i++)
                    {
                        var dup = list[i];
                        logger?.LogWarning("Phát hiện tài khoản trùng email: {Email}, Id: {Id}. Đặt EmailNormalized = null.", dup.Email, dup.Id);
                        if (dup.EmailNormalized != null)
                        {
                            await context.Users.UpdateOneAsync(
                                Builders<User>.Filter.Eq(u => u.Id, dup.Id),
                                Builders<User>.Update.Set<string?>(u => u.EmailNormalized, null));
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                logger?.LogWarning(ex, "Lỗi trong migration Users.");
            }

            // B. MealPlans Migration (Chuẩn hóa StartDate về Thứ Hai UTC+7 và Deduplicate)
            try
            {
                var allPlans = await context.MealPlans.Find(m => !m.IsDeleted).ToListAsync();
                foreach (var plan in allPlans)
                {
                    if (DateTime.TryParse(plan.StartDate, out var dt))
                    {
                        int diff = (7 + (dt.DayOfWeek - DayOfWeek.Monday)) % 7;
                        var mondayStr = dt.AddDays(-1 * diff).Date.ToString("yyyy-MM-dd");
                        if (plan.StartDate != mondayStr)
                        {
                            plan.StartDate = mondayStr;
                            await context.MealPlans.UpdateOneAsync(
                                Builders<MealPlan>.Filter.Eq(m => m.Id, plan.Id),
                                Builders<MealPlan>.Update.Set(m => m.StartDate, mondayStr));
                        }
                    }
                }

                var planGroups = allPlans
                    .Where(p => !string.IsNullOrEmpty(p.UserId) && !string.IsNullOrEmpty(p.StartDate))
                    .GroupBy(p => new { p.UserId, p.StartDate });

                foreach (var g in planGroups)
                {
                    var list = g.OrderByDescending(p => p.UpdatedAt ?? p.CreatedAt).ToList();
                    if (list.Count > 1)
                    {
                        for (int i = 1; i < list.Count; i++)
                        {
                            await context.MealPlans.UpdateOneAsync(
                                Builders<MealPlan>.Filter.Eq(m => m.Id, list[i].Id),
                                Builders<MealPlan>.Update.Set(m => m.IsDeleted, true).Set(m => m.DeletedAt, DateTime.UtcNow));
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                logger?.LogWarning(ex, "Lỗi trong migration MealPlans.");
            }

            // C. HealthProfiles Migration (Ánh xạ alias goal cũ)
            try
            {
                var oldGoalProfiles = await context.HealthProfiles.Find(h =>
                    !h.IsDeleted && (h.Goal == "lose" || h.Goal == "gain" || h.Goal == "weight_loss")).ToListAsync();

                foreach (var hp in oldGoalProfiles)
                {
                    var mappedGoal = hp.Goal switch
                    {
                        "lose" or "weight_loss" => "lose_weight",
                        "gain" => "gain_weight",
                        _ => hp.Goal
                    };
                    await context.HealthProfiles.UpdateOneAsync(
                        Builders<HealthProfile>.Filter.Eq(h => h.Id, hp.Id),
                        Builders<HealthProfile>.Update.Set(h => h.Goal, mappedGoal));
                }
            }
            catch (Exception ex)
            {
                logger?.LogWarning(ex, "Lỗi trong migration HealthProfiles.");
            }

            // D. PantryItems Migration (Backfill NormalizedName & Deduplicate)
            try
            {
                var pantryCol = context.PantryItems;
                var allPantryItems = await pantryCol.Find(p => !p.IsDeleted).ToListAsync();

                foreach (var pItem in allPantryItems)
                {
                    var norm = DomainLayer.Helpers.AllergyMatcher.RemoveDiacritics(pItem.Ingredient ?? string.Empty).ToLowerInvariant();
                    if (string.IsNullOrEmpty(pItem.NormalizedName) || pItem.NormalizedName != norm)
                    {
                        pItem.NormalizedName = norm;
                        await pantryCol.UpdateOneAsync(
                            Builders<PantryItem>.Filter.Eq(x => x.Id, pItem.Id),
                            Builders<PantryItem>.Update.Set(x => x.NormalizedName, norm));
                    }
                }

                var grouped = allPantryItems
                    .Where(p => !string.IsNullOrEmpty(p.UserId) && !string.IsNullOrEmpty(p.NormalizedName))
                    .GroupBy(p => new { p.UserId, p.NormalizedName });

                foreach (var group in grouped)
                {
                    var list = group.OrderByDescending(p => p.UpdatedAt ?? p.CreatedAt).ToList();
                    if (list.Count > 1)
                    {
                        for (int i = 1; i < list.Count; i++)
                        {
                            await pantryCol.UpdateOneAsync(
                                Builders<PantryItem>.Filter.Eq(x => x.Id, list[i].Id),
                                Builders<PantryItem>.Update.Set(x => x.IsDeleted, true).Set(x => x.DeletedAt, DateTime.UtcNow));
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                logger?.LogWarning(ex, "Lỗi trong migration PantryItems.");
            }
        }
    }
}

