using System;
using System.Collections.Generic;
using System.Linq.Expressions;
using System.Threading.Tasks;
using DomainLayer.Entities;
using DomainLayer.Interfaces;
using InfrastructureLayer.Database;
using MongoDB.Driver;

namespace InfrastructureLayer.Repository
{
    public class GenericRepository<T> : IGenericRepository<T> where T : class, IEntity
    {
        protected readonly IMongoCollection<T> _collection;

        public GenericRepository(MongoDbContext context)
        {
            var collectionName = GetDefaultCollectionName();
            _collection = context.Database.GetCollection<T>(collectionName);
        }

        public GenericRepository(MongoDbContext context, string collectionName)
        {
            _collection = context.Database.GetCollection<T>(collectionName);
        }

        private static string GetDefaultCollectionName()
        {
            var name = typeof(T).Name;
            return name.EndsWith("s", StringComparison.OrdinalIgnoreCase) ? name : $"{name}s";
        }

        public async Task<T> CreateAsync(T entity)
        {
            await _collection.InsertOneAsync(entity);
            return entity;
        }

        public async Task DeleteAsync(string id)
        {
            if (string.IsNullOrWhiteSpace(id) || !MongoDB.Bson.ObjectId.TryParse(id, out _)) return;
            await _collection.DeleteOneAsync(x => x.Id == id);
        }

        public async Task<IEnumerable<T>> FindAsync(Expression<Func<T, bool>> predicate)
        {
            return await _collection.Find(predicate).ToListAsync();
        }

        public async Task<T?> FindByIdAsync(string id)
        {
            if (string.IsNullOrWhiteSpace(id) || !MongoDB.Bson.ObjectId.TryParse(id, out _)) return null;
            return await _collection.Find(x => x.Id == id).FirstOrDefaultAsync();
        }

        public async Task<T?> FirstOrDefaultAsync(Expression<Func<T, bool>> predicate)
        {
            return await _collection.Find(predicate).FirstOrDefaultAsync();
        }

        public async Task<IEnumerable<T>> GetAllAsync()
        {
            return await _collection.Find(_ => true).ToListAsync();
        }

        public async Task UpdateAsync(string id, T entity)
        {
            if (string.IsNullOrWhiteSpace(id) || !MongoDB.Bson.ObjectId.TryParse(id, out _)) return;
            await _collection.ReplaceOneAsync(x => x.Id == id, entity);
        }

        public async Task<long> CountAsync(Expression<Func<T, bool>> predicate)
        {
            return await _collection.CountDocumentsAsync(predicate);
        }

        public async Task<IEnumerable<T>> FindPagedAsync(
            Expression<Func<T, bool>> predicate,
            int page,
            int pageSize,
            Expression<Func<T, object>>? sortAsc = null,
            Expression<Func<T, object>>? sortDesc = null)
        {
            page = Math.Max(1, page);
            pageSize = Math.Max(1, pageSize);
            var skip = (page - 1) * pageSize;

            var findFluent = _collection.Find(predicate);
            if (sortAsc != null)
            {
                findFluent = findFluent.Sort(Builders<T>.Sort.Ascending(sortAsc).Descending(x => x.Id));
            }
            else if (sortDesc != null)
            {
                findFluent = findFluent.Sort(Builders<T>.Sort.Descending(sortDesc).Descending(x => x.Id));
            }
            else
            {
                findFluent = findFluent.Sort(Builders<T>.Sort.Descending(x => x.Id));
            }

            return await findFluent.Skip(skip).Limit(pageSize).ToListAsync();
        }

        // B15: Cursor pagination query trực tiếp MongoDB theo _id giảm dần
        public async Task<IEnumerable<T>> FindCursorAsync(
            Expression<Func<T, bool>> predicate,
            string? lastId,
            int limit)
        {
            var filter = Builders<T>.Filter.Where(predicate);
            if (!string.IsNullOrEmpty(lastId))
            {
                filter = filter & Builders<T>.Filter.Lt(x => x.Id, lastId);
            }

            return await _collection.Find(filter)
                .Sort(Builders<T>.Sort.Descending(x => x.Id))
                .Limit(limit)
                .ToListAsync();
        }

        // B17: Overload 3 tham số mặc định touchUpdatedAt: false để không làm vỡ các Moq test cũ
        public async Task<bool> IncrementFieldAsync(string id, Expression<Func<T, int>> field, int value = 1)
        {
            return await IncrementFieldAsync(id, field, value, touchUpdatedAt: false);
        }

        public async Task<bool> IncrementFieldAsync(string id, Expression<Func<T, int>> field, int value, bool touchUpdatedAt)
        {
            var update = Builders<T>.Update.Inc(field, value);
            if (touchUpdatedAt && typeof(BaseEntity).IsAssignableFrom(typeof(T)))
            {
                update = update.Set("UpdatedAt", DateTime.UtcNow);
            }
            var result = await _collection.UpdateOneAsync(x => x.Id == id, update);
            return result.ModifiedCount > 0;
        }

        public async Task<bool> UpdateFieldAsync<TField>(string id, Expression<Func<T, TField>> field, TField value)
        {
            var update = Builders<T>.Update.Set(field, value);
            if (typeof(BaseEntity).IsAssignableFrom(typeof(T)))
            {
                update = update.Set("UpdatedAt", DateTime.UtcNow);
            }
            var result = await _collection.UpdateOneAsync(x => x.Id == id, update);
            return result.ModifiedCount > 0;
        }

        public async Task<bool> UpdateFieldsAsync(string id, UpdateDefinition<T> update)
        {
            if (typeof(BaseEntity).IsAssignableFrom(typeof(T)))
            {
                update = update.Set("UpdatedAt", DateTime.UtcNow);
            }
            var result = await _collection.UpdateOneAsync(x => x.Id == id, update);
            return result.ModifiedCount > 0;
        }
    }
}
