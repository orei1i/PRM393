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

        private static readonly HashSet<string> ValidActivities = new(StringComparer.OrdinalIgnoreCase)
        {
            "sedentary", "light", "moderate", "active"
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
            // B41: bữa lạ sẽ thành một ô bữa không ai đọc được khi tạo thực đơn. "snack" là tên cũ, vẫn nhận.
            if (request.MealPattern != null && request.MealPattern.Any(slot =>
                    string.IsNullOrWhiteSpace(slot) ||
                    (!RecipeRules.MealSlots.Contains(slot.Trim()) && !string.Equals(slot.Trim(), "snack", StringComparison.OrdinalIgnoreCase))))
            {
                throw new BadRequestException("Bữa ăn không hợp lệ. Các bữa hợp lệ: breakfast, snack_am, lunch, snack_pm, dinner, snack_late.", "invalid_slot");
            }

            var existing = await _profileRepo.FirstOrDefaultAsync(x => x.UserId == userId && !x.IsDeleted);

            // B43: Chuẩn hóa goal và ánh xạ alias cũ (lose -> lose_weight, gain -> gain_weight)
            string goalToSave;
            if (!string.IsNullOrWhiteSpace(request.Goal))
            {
                var g = request.Goal.Trim().ToLowerInvariant();
                goalToSave = g switch
                {
                    "lose" or "giảm cân" or "giam_can" or "weight_loss" => "lose_weight",
                    "gain" or "tăng cân" or "tang_can" => "gain_weight",
                    "giữ cân" or "giu_can" => "maintain",
                    "muscle" or "tăng cơ" => "gain_muscle",
                    _ when ValidGoals.Contains(g) => g,
                    _ => throw new BadRequestException("Mục tiêu dinh dưỡng không hợp lệ. Các mục tiêu hợp lệ: lose_weight, maintain, lean_muscle, gain_weight, eat_clean, gain_muscle.")
                };
            }
            else
            {
                // Giữ nguyên goal cũ, chuẩn hóa nếu là alias cũ
                var oldGoal = existing?.Goal?.ToLowerInvariant() ?? "maintain";
                goalToSave = oldGoal switch
                {
                    "lose" or "weight_loss" => "lose_weight",
                    "gain" => "gain_weight",
                    _ => ValidGoals.Contains(oldGoal) ? oldGoal : "maintain"
                };
            }

            // B67: Chuẩn hóa Gender (chỉ nhận Male hoặc Female khi ghi)
            string effectiveGender;
            if (!string.IsNullOrWhiteSpace(request.Gender))
            {
                var g = request.Gender.Trim().ToLowerInvariant();
                effectiveGender = g switch
                {
                    "male" or "nam" => "Male",
                    "female" or "nữ" or "nu" => "Female",
                    _ => throw new BadRequestException("Giới tính chỉ nhận 'Male' hoặc 'Female'.")
                };
            }
            else if (existing != null)
            {
                // Nếu hồ sơ cũ có 'Other' mà PUT không gửi lại giới tính -> yêu cầu chọn lại
                if (string.Equals(existing.Gender, "Other", StringComparison.OrdinalIgnoreCase))
                {
                    throw new BadRequestException("Hồ sơ cũ có giới tính 'Other'. Vui lòng cập nhật giới tính thành 'Male' hoặc 'Female'.");
                }
                effectiveGender = existing.Gender;
            }
            else
            {
                throw new BadRequestException("Giới tính và năm sinh là bắt buộc khi tạo hồ sơ lần đầu.");
            }

            // B9: ActivityLevel (sedentary, light, moderate, active)
            string effectiveActivityLevel;
            if (!string.IsNullOrWhiteSpace(request.ActivityLevel))
            {
                var act = request.ActivityLevel.Trim().ToLowerInvariant();
                if (!ValidActivities.Contains(act))
                {
                    throw new BadRequestException("Mức độ hoạt động không hợp lệ. Các mức hợp lệ: sedentary, light, moderate, active.");
                }
                effectiveActivityLevel = act;
            }
            else
            {
                effectiveActivityLevel = existing?.ActivityLevel ?? "light";
            }

            // B9: BirthYear
            if (existing == null && !request.BirthYear.HasValue)
            {
                throw new BadRequestException("Giới tính và năm sinh là bắt buộc khi tạo hồ sơ lần đầu.");
            }
            var effectiveBirthYear = (request.BirthYear.HasValue && request.BirthYear.Value > 0)
                ? request.BirthYear.Value
                : (existing?.BirthYear ?? 1998);

            var (bmr, tdee, targetCalories, bmi, bmiCategory) = EnergyCalculator.ComputeAll(
                effectiveGender,
                effectiveBirthYear,
                request.HeightCm,
                request.WeightKg,
                effectiveActivityLevel,
                goalToSave);

            // B9 & B68: Allergies (nếu request.Allergies == null thì giữ nguyên cũ)
            List<string> allergyKeys;
            if (request.Allergies != null)
            {
                allergyKeys = new List<string>();
                foreach (var item in request.Allergies)
                {
                    var standardId = !string.IsNullOrWhiteSpace(item.AllergenId) && AllergyMatcher.IsStandardAllergen(item.AllergenId)
                        ? item.AllergenId
                        : AllergyMatcher.NormalizeToId(item.Name);

                    var key = standardId ?? item.Name.Trim();
                    if (!string.IsNullOrWhiteSpace(key) && !allergyKeys.Contains(key))
                    {
                        allergyKeys.Add(key);
                    }
                }
            }
            else
            {
                allergyKeys = existing?.Allergies ?? new List<string>();
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
                    ActivityLevel = effectiveActivityLevel,
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
                existing.Gender = effectiveGender;
                existing.BirthYear = effectiveBirthYear;
                existing.ActivityLevel = effectiveActivityLevel;
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
                    Source = "profile",
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

        // ─────────────────────────────────────────────────────────────────────
        // LOG METRICS (B36, B37)
        // ─────────────────────────────────────────────────────────────────────
        public async Task<HealthMetricLogResponse> LogMetricsAsync(string userId, LogMetricsRequest request)
        {
            // B36: Bắt buộc ít nhất một chỉ số cơ thể
            if (!request.WeightKg.HasValue && !request.HeightCm.HasValue && !request.WaistCm.HasValue && !request.BodyFatPct.HasValue)
            {
                throw new BadRequestException("Phải cung cấp ít nhất một chỉ số cơ thể.");
            }

            // B36: Trả 404 nếu chưa có hồ sơ sức khỏe
            var profile = await _profileRepo.FirstOrDefaultAsync(p => p.UserId == userId && !p.IsDeleted);
            if (profile == null)
            {
                throw new NotFoundException("Chưa tạo hồ sơ sức khỏe. Vui lòng thiết lập hồ sơ trước khi ghi nhận chỉ số.");
            }

            var height = request.HeightCm ?? profile.HeightCm;
            var weight = request.WeightKg ?? profile.WeightKg;
            var bmi = EnergyCalculator.CalculateBmi(height, weight);

            var log = new HealthMetricLog
            {
                UserId = userId,
                HeightCm = height,
                WeightKg = weight,
                Bmi = bmi,
                WaistCm = request.WaistCm,
                BodyFatPct = request.BodyFatPct,
                Source = string.IsNullOrWhiteSpace(request.Source) ? "check_in" : request.Source.Trim(),
                LoggedAt = DateTime.UtcNow
            };

            await _logRepo.CreateAsync(log);

            // B37: Tự động tính toán lại BMI, BMR, TDEE, Calo mục tiêu và cập nhật Profile
            if (request.WeightKg.HasValue || request.HeightCm.HasValue)
            {
                profile.WeightKg = weight;
                profile.HeightCm = height;
                profile.Bmi = bmi;
                profile.BmiCategory = EnergyCalculator.CategorizeBmi(bmi);

                var age = Math.Clamp(DateTime.UtcNow.Year - profile.BirthYear, 13, 100);
                profile.Bmr = Math.Round(EnergyCalculator.CalculateBmr(profile.Gender, weight, height, age), 1);
                var factor = EnergyCalculator.GetActivityFactor(profile.ActivityLevel);
                profile.Tdee = Math.Round(profile.Bmr * factor, 1);

                var goalAdjustment = EnergyCalculator.GetGoalAdjustment(profile.Goal);
                profile.TargetCalories = EnergyCalculator.RoundToDisplayCalories(profile.Tdee * (1.0 + goalAdjustment));
                profile.UpdatedAt = DateTime.UtcNow;

                await _profileRepo.UpdateAsync(profile.Id, profile);

                // Đồng bộ sang thực đơn tuần hiện tại nếu có
                try
                {
                    var vnNow = DateTime.UtcNow.AddHours(7).Date;
                    int diff = (7 + (vnNow.DayOfWeek - DayOfWeek.Monday)) % 7;
                    var currentMonday = vnNow.AddDays(-1 * diff).ToString("yyyy-MM-dd");

                    var currentPlan = await _mealPlanRepo.FirstOrDefaultAsync(p => p.UserId == userId && p.StartDate == currentMonday && !p.IsDeleted);
                    if (currentPlan != null)
                    {
                        currentPlan.Goal = profile.Goal;
                        currentPlan.DailyTargets.Calories = profile.TargetCalories;
                        currentPlan.DailyTargets.ProteinG = Math.Round(profile.TargetCalories * 0.15 / 4.0, 1);
                        currentPlan.DailyTargets.CarbsG = Math.Round(profile.TargetCalories * 0.55 / 4.0, 1);
                        currentPlan.DailyTargets.FatG = Math.Round(profile.TargetCalories * 0.30 / 9.0, 1);
                        currentPlan.UpdatedAt = DateTime.UtcNow;
                        await _mealPlanRepo.UpdateAsync(currentPlan.Id, currentPlan);
                    }
                }
                catch
                {
                    // Bỏ qua nếu tuần chưa có thực đơn
                }
            }

            return new HealthMetricLogResponse
            {
                Id = log.Id,
                HeightCm = log.HeightCm,
                WeightKg = log.WeightKg,
                Bmi = log.Bmi,
                WaistCm = log.WaistCm,
                BodyFatPct = log.BodyFatPct,
                LoggedAt = log.LoggedAt,
                Source = log.Source
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
                LoggedAt = l.LoggedAt,
                Source = l.Source
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

        /// <summary>B43: dòng cũ chưa kịp migrate vẫn đọc đúng mục tiêu, không rơi về maintain.</summary>
        private static string ReadGoal(string? goal)
        {
            var value = goal?.Trim().ToLowerInvariant() ?? "maintain";
            return value switch
            {
                "lose" or "weight_loss" => "lose_weight",
                "gain" => "gain_weight",
                _ => ValidGoals.Contains(value) ? value : "maintain"
            };
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
                Goal = ReadGoal(profile.Goal),
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
