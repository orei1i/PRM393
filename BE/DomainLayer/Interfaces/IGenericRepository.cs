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
    }
}