using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Pantry;

namespace ApplicationLayer.Interfaces
{
    public interface IPantryService
    {
        Task<IEnumerable<PantryItemResponse>> GetPantryItemsAsync(string userId, int? expiringInDays);
        Task<PantryItemResponse> AddPantryItemAsync(string userId, AddPantryItemRequest request);
        Task<IEnumerable<PantryItemResponse>> AddPantryItemsBatchAsync(string userId, List<AddPantryItemRequest> requests);
        Task<PantryItemResponse> UpdatePantryItemAsync(string userId, string id, UpdatePantryItemRequest request);
        Task<bool> DeletePantryItemAsync(string userId, string id);
        Task<bool> ClearPantryAsync(string userId);

        Task<IEnumerable<IngredientResponse>> SearchIngredientsAsync(string? q, bool veganOnly = true);
        Task<IngredientResponse> GetIngredientByIdAsync(string id);
    }
}

