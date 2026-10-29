using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.HealthProfile;
using ApplicationLayer.Interfaces;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;

namespace ApplicationLayer.Services
{
    public class HealthProfileService : IHealthProfileService
    {
        private readonly IGenericRepository<HealthProfile> _profileRepo;
        private readonly IGenericRepository<HealthMetricLog> _logRepo;

        public HealthProfileService(
            IGenericRepository<HealthProfile> profileRepo,
            IGenericRepository<HealthMetricLog> logRepo)
        {
            _profileRepo = profileRepo;
            _logRepo = logRepo;
        }

        public async Task<HealthProfileResponse> GetMyHealthProfileAsync(string userId)
        {
            var profile = await _profileRepo.FirstOrDefaultAsync(x => x.UserId == userId && !x.IsDeleted);
            if (profile == null)
            {
                throw new NotFoundException("Bạn chưa tạo hồ sơ sức khỏe.");
            }

            return MapToResponse(profile);
        }

        public async Task<HealthProfileResponse> UpdateMyHealthProfileAsync(string userId, UpdateHealthProfileRequest request)
        {
            var existing = await _profileRepo.FirstOrDefaultAsync(x => x.UserId == userId && !x.IsDeleted);

            var (bmr, tdee, targetCalories, bmi, bmiCategory) = EnergyCalculator.ComputeAll(
                request.Gender,
                request.BirthYear,
                request.HeightCm,
                request.WeightKg,
                request.ActivityLevel,
                request.Goal);

            var allergyKeys = new List<string>();
            if (request.Allergies != null)
            {
                foreach (var item in request.Allergies)
                {
                    var key = !string.IsNullOrWhiteSpace(item.AllergenId) && AllergyMatcher.IsStandardAllergen(item.AllergenId)
                        ? item.AllergenId
                        : item.Name;
                    if (!string.IsNullOrWhiteSpace(key) && !allergyKeys.Contains(key))
                    {
                        allergyKeys.Add(key);
                    }
                }
            }

            var previousWeight = existing?.WeightKg;

            if (existing == null)
            {
                existing = new HealthProfile
                {
                    UserId = userId,
                    HeightCm = request.HeightCm,
                    WeightKg = request.WeightKg,
                    Bmi = bmi,
                    BmiCategory = bmiCategory,
                    Goal = request.Goal,
                    Gender = request.Gender,
                    BirthYear = request.BirthYear,
                    ActivityLevel = request.ActivityLevel,
                    MealPattern = request.MealPattern?.Any() == true
                        ? request.MealPattern
                        : new List<string> { "breakfast", "lunch", "dinner" },
                    Allergies = allergyKeys,
                    DietaryRestrictions = request.DietaryRestrictions ?? new List<string>(),
                    Bmr = bmr,
                    Tdee = tdee,
                    TargetCalories = targetCalories,
                    CreatedAt = DateTime.UtcNow
                };

                await _profileRepo.CreateAsync(existing);
            }
            else
            {
                existing.HeightCm = request.HeightCm;
                existing.WeightKg = request.WeightKg;
                existing.Bmi = bmi;
                existing.BmiCategory = bmiCategory;
                existing.Goal = request.Goal;
                existing.Gender = request.Gender;
                existing.BirthYear = request.BirthYear;
                existing.ActivityLevel = request.ActivityLevel;
                if (request.MealPattern?.Any() == true)
                {
                    existing.MealPattern = request.MealPattern;
                }
                existing.Allergies = allergyKeys;
                if (request.DietaryRestrictions != null)
                {
                    existing.DietaryRestrictions = request.DietaryRestrictions;
                }
                existing.Bmr = bmr;
                existing.Tdee = tdee;
                existing.TargetCalories = targetCalories;
                existing.UpdatedAt = DateTime.UtcNow;

                await _profileRepo.UpdateAsync(existing.Id, existing);
            }

            // Ghi nhật ký biến thiên cân nặng nếu lần đầu tạo hoặc cân nặng thay đổi
            if (previousWeight == null || Math.Abs(previousWeight.Value - request.WeightKg) > 0.05)
            {
                var metricLog = new HealthMetricLog
                {
                    UserId = userId,
                    WeightKg = request.WeightKg,
                    HeightCm = request.HeightCm,
                    Bmi = bmi,
                    LoggedAt = DateTime.UtcNow
                };
                await _logRepo.CreateAsync(metricLog);
            }

            return MapToResponse(existing);
        }

        public async Task<IEnumerable<HealthMetricLogResponse>> GetMetricsHistoryAsync(string userId, int limit = 30)
        {
            limit = Math.Clamp(limit, 1, 100);
            var logs = await _logRepo.FindPagedAsync(
                x => x.UserId == userId && !x.IsDeleted,
                page: 1,
                pageSize: limit,
                sortDesc: x => x.LoggedAt);

            return logs.Select(l => new HealthMetricLogResponse
            {
                Id = l.Id,
                WeightKg = l.WeightKg,
                HeightCm = l.HeightCm,
                Bmi = l.Bmi,
                LoggedAt = l.LoggedAt
            });
        }

        public IEnumerable<AllergenResponse> GetAllergens()
        {
            return AllergyMatcher.StandardAllergenIds.Select(id => new AllergenResponse
            {
                AllergenId = id,
                Name = AllergyMatcher.StandardAllergenLabels.TryGetValue(id, out var label) ? label : id,
                Description = $"Dị ứng liên quan đến {id}"
            });
        }

        private static HealthProfileResponse MapToResponse(HealthProfile profile)
        {
            return new HealthProfileResponse
            {
                Id = profile.Id,
                UserId = profile.UserId,
                HeightCm = profile.HeightCm,
                WeightKg = profile.WeightKg,
                Bmi = profile.Bmi,
                BmiCategory = profile.BmiCategory,
                Goal = profile.Goal,
                Gender = profile.Gender,
                BirthYear = profile.BirthYear,
                ActivityLevel = profile.ActivityLevel,
                MealPattern = profile.MealPattern,
                Allergies = profile.Allergies.Select(a => new AllergyItemDto
                {
                    AllergenId = AllergyMatcher.IsStandardAllergen(a) ? a : null,
                    Name = AllergyMatcher.IsStandardAllergen(a) && AllergyMatcher.StandardAllergenLabels.TryGetValue(a, out var l) ? l : a
                }).ToList(),
                DietaryRestrictions = profile.DietaryRestrictions,
                Bmr = profile.Bmr,
                Tdee = profile.Tdee,
                TargetCalories = profile.TargetCalories
            };
        }
    }
}

