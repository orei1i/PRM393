using System.Collections.Generic;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.HealthProfile;

namespace ApplicationLayer.Interfaces
{
    public interface IHealthProfileService
    {
        Task<HealthProfileResponse> GetMyHealthProfileAsync(string userId);
        Task<HealthProfileResponse> UpdateMyHealthProfileAsync(string userId, UpdateHealthProfileRequest request);
        Task<IEnumerable<HealthMetricLogResponse>> GetMetricsHistoryAsync(string userId, int limit = 30);
        IEnumerable<AllergenResponse> GetAllergens();
    }
}

