using System;
using System.Collections.Generic;
using System.Linq.Expressions;
using System.Threading.Tasks;

namespace DomainLayer.Interfaces
{
    public interface IGenericRepository<T> where T : class, IEntity
    {
        Task<T> CreateAsync(T entity);
        Task<T?> FindByIdAsync(string id);
        Task<IEnumerable<T>> FindAsync(Expression<Func<T, bool>> predicate);
        Task<T?> FirstOrDefaultAsync(Expression<Func<T, bool>> predicate);
        Task UpdateAsync(string id, T entity);
        Task DeleteAsync(string id);
        Task<IEnumerable<T>> GetAllAsync();
        Task<long> CountAsync(Expression<Func<T, bool>> predicate);
        Task<IEnumerable<T>> FindPagedAsync(
            Expression<Func<T, bool>> predicate,
            int page,
            int pageSize,
            Expression<Func<T, object>>? sortAsc = null,
            Expression<Func<T, object>>? sortDesc = null);
        Task<bool> IncrementFieldAsync(string id, Expression<Func<T, int>> field, int value = 1);
        Task<bool> UpdateFieldAsync<TField>(string id, Expression<Func<T, TField>> field, TField value);
    }
}