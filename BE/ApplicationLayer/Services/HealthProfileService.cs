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
        private readonly IGenericRepository<MealPlan> _mealPlanRepo;

        private static readonly HashSet<string> ValidGoals = new(StringComparer.OrdinalIgnoreCase)
        {
            "lose_weight", "maintain", "lean_muscle", "gain_weight", "eat_clean", "gain_muscle"
        };

        public HealthProfileService(
            IGenericRepository<HealthProfile> profileRepo,
            IGenericRepository<HealthMetricLog> logRepo,
            IGenericRepository<MealPlan> mealPlanRepo)
        {
            _profileRepo = profileRepo;
            _logRepo = logRepo;
            _mealPlanRepo = mealPlanRepo;
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
            // B10: Validate whitelist goal khi ghi
            if (!string.IsNullOrWhiteSpace(request.Goal) && !ValidGoals.Contains(request.Goal.Trim()))
            {
                throw new BadRequestException("Mục tiêu dinh dưỡng không hợp lệ. Các mục tiêu hợp lệ: lose_weight, maintain, lean_muscle, gain_weight, eat_clean, gain_muscle.");
            }

            var goalToSave = string.IsNullOrWhiteSpace(request.Goal) ? "maintain" : request.Goal.Trim().ToLowerInvariant();
            var existing = await _profileRepo.FirstOrDefaultAsync(x => x.UserId == userId && !x.IsDeleted);

            // B9: Gender và BirthYear bắt buộc khi tạo lần đầu, cho phép null khi cập nhật
            if (existing == null)
            {
                if (string.IsNullOrWhiteSpace(request.Gender) || !request.BirthYear.HasValue)
                {
                    throw new BadRequestException("Giới tính và năm sinh là bắt buộc khi tạo hồ sơ lần đầu.");
                }
            }

            var effectiveGender = !string.IsNullOrWhiteSpace(request.Gender)
                ? request.Gender
                : (existing?.Gender ?? "Other");

            var effectiveBirthYear = (request.BirthYear.HasValue && request.BirthYear.Value > 0)
                ? request.BirthYear.Value
                : (existing?.BirthYear ?? 1998);

            var (bmr, tdee, targetCalories, bmi, bmiCategory) = EnergyCalculator.ComputeAll(
                effectiveGender,
                effectiveBirthYear,
                request.HeightCm,
                request.WeightKg,
                request.ActivityLevel,
                goalToSave);

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
                    Goal = goalToSave,
                    Gender = effectiveGender,
                    BirthYear = effectiveBirthYear,
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
                existing.Goal = goalToSave;
                if (!string.IsNullOrWhiteSpace(request.Gender))
                {
                    existing.Gender = request.Gender;
                }
                if (request.BirthYear.HasValue && request.BirthYear.Value > 0)
                {
                    existing.BirthYear = request.BirthYear.Value;
                }
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

            // B8: Đồng bộ DailyTargets và Goal vào thực đơn tuần hiện tại nếu có
            try
            {
                var vnNow = DateTime.UtcNow.AddHours(7).Date;
                int diff = (7 + (vnNow.DayOfWeek - DayOfWeek.Monday)) % 7;
                var currentMonday = vnNow.AddDays(-1 * diff).ToString("yyyy-MM-dd");

                var currentPlan = await _mealPlanRepo.FirstOrDefaultAsync(p => p.UserId == userId && p.StartDate == currentMonday && !p.IsDeleted);
                if (currentPlan != null)
                {
                    currentPlan.Goal = existing.Goal;
                    currentPlan.DailyTargets.Calories = existing.TargetCalories;
                    currentPlan.DailyTargets.ProteinG = Math.Round(existing.TargetCalories * 0.15 / 4.0, 1);
                    currentPlan.DailyTargets.CarbsG = Math.Round(existing.TargetCalories * 0.55 / 4.0, 1);
                    currentPlan.DailyTargets.FatG = Math.Round(existing.TargetCalories * 0.30 / 9.0, 1);
                    currentPlan.UpdatedAt = DateTime.UtcNow;
                    await _mealPlanRepo.UpdateAsync(currentPlan.Id, currentPlan);
                }
            }
            catch
            {
                // B8: Nếu chưa có thực đơn hoặc có lỗi query, bỏ qua
            }

            return MapToResponse(existing);
        }

        public async Task<HealthMetricLogResponse> LogMetricsAsync(string userId, LogMetricsRequest request)
        {
            var profile = await _profileRepo.FirstOrDefaultAsync(p => p.UserId == userId && !p.IsDeleted);
            var height = request.HeightCm ?? profile?.HeightCm ?? 170.0;
            var weight = request.WeightKg ?? profile?.WeightKg ?? 65.0;
            var bmi = EnergyCalculator.CalculateBmi(height, weight);

            var log = new HealthMetricLog
            {
                UserId = userId,
                HeightCm = height,
                WeightKg = weight,
                Bmi = bmi,
                WaistCm = request.WaistCm,
                BodyFatPct = request.BodyFatPct,
                LoggedAt = DateTime.UtcNow
            };

            await _logRepo.CreateAsync(log);

            if (profile != null && (request.WeightKg.HasValue || request.HeightCm.HasValue))
            {
                if (request.WeightKg.HasValue) profile.WeightKg = request.WeightKg.Value;
                if (request.HeightCm.HasValue) profile.HeightCm = request.HeightCm.Value;
                profile.Bmi = bmi;
                profile.BmiCategory = EnergyCalculator.CategorizeBmi(bmi);
                profile.UpdatedAt = DateTime.UtcNow;
                await _profileRepo.UpdateAsync(profile.Id, profile);
            }

            return new HealthMetricLogResponse
            {
                Id = log.Id,
                HeightCm = log.HeightCm,
                WeightKg = log.WeightKg,
                Bmi = log.Bmi,
                WaistCm = log.WaistCm,
                BodyFatPct = log.BodyFatPct,
                LoggedAt = log.LoggedAt
            };
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
                WaistCm = l.WaistCm,
                BodyFatPct = l.BodyFatPct,
                LoggedAt = l.LoggedAt
            });
        }

        // ─── B20: Lọc dị ứng theo query q ─────────────────────────────────────
        public IEnumerable<AllergenResponse> GetAllergens(string? q = null)
        {
            var all = AllergyMatcher.StandardAllergenIds.Select(id => new AllergenResponse
            {
                AllergenId = id,
                Name = AllergyMatcher.StandardAllergenLabels.TryGetValue(id, out var label) ? label : id,
                Description = $"Dị ứng liên quan đến {id}"
            });

            if (string.IsNullOrWhiteSpace(q))
                return all;

            var qNorm = AllergyMatcher.RemoveDiacritics(q.Trim()).ToLowerInvariant();
            return all.Where(a =>
                AllergyMatcher.RemoveDiacritics(a.AllergenId).ToLowerInvariant().Contains(qNorm) ||
                AllergyMatcher.RemoveDiacritics(a.Name).ToLowerInvariant().Contains(qNorm));
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
                // B10: Fallback về maintain nếu gặp giá trị lạ trong DB cũ
                Goal = ValidGoals.Contains(profile.Goal) ? profile.Goal : "maintain",
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
