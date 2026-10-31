using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.HealthProfile;
using ApplicationLayer.Services;
using DomainLayer.Entities;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;
using Moq;
using Xunit;

namespace VeganLife.Tests
{
    public class Sprint3_HealthProfileUnitTests
    {
        private readonly Mock<IGenericRepository<HealthProfile>> _profileRepoMock;
        private readonly Mock<IGenericRepository<HealthMetricLog>> _logRepoMock;
        private readonly Mock<IGenericRepository<MealPlan>> _mealPlanRepoMock;
        private readonly HealthProfileService _service;

        public Sprint3_HealthProfileUnitTests()
        {
            _profileRepoMock = new Mock<IGenericRepository<HealthProfile>>();
            _logRepoMock = new Mock<IGenericRepository<HealthMetricLog>>();
            _mealPlanRepoMock = new Mock<IGenericRepository<MealPlan>>();

            _service = new HealthProfileService(
                _profileRepoMock.Object,
                _logRepoMock.Object,
                _mealPlanRepoMock.Object);
        }

        [Fact]
        public async Task B10_UpdateProfile_WithInvalidGoal_ThrowsBadRequestException()
        {
            var userId = "user123";
            var request = new UpdateHealthProfileRequest
            {
                HeightCm = 170,
                WeightKg = 65,
                Goal = "super_muscles_invalid",
                Gender = "Male",
                BirthYear = 1995
            };

            // B10: Goal lạ không nằm trong whitelist phải ném BadRequestException
            await Assert.ThrowsAsync<BadRequestException>(() => _service.UpdateMyHealthProfileAsync(userId, request));
        }

        [Fact]
        public async Task B10_UpdateProfile_WithValidGoals_Succeeds()
        {
            var userId = "user123";
            _profileRepoMock.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<HealthProfile, bool>>>()))
                .ReturnsAsync((HealthProfile?)null);

            var validGoals = new[] { "lose_weight", "maintain", "lean_muscle", "gain_weight", "eat_clean", "gain_muscle" };

            foreach (var goal in validGoals)
            {
                var request = new UpdateHealthProfileRequest
                {
                    HeightCm = 175,
                    WeightKg = 70,
                    Goal = goal,
                    Gender = "Male",
                    BirthYear = 1996
                };

                var response = await _service.UpdateMyHealthProfileAsync(userId, request);
                Assert.NotNull(response);
                Assert.Equal(goal, response.Goal);
            }
        }

        [Fact]
        public async Task B10_GetProfile_WithUnknownGoalInDb_FallsBackToMaintain()
        {
            var userId = "user123";
            var profileInDb = new HealthProfile
            {
                Id = "p1",
                UserId = userId,
                HeightCm = 170,
                WeightKg = 60,
                Goal = "legacy_unknown_goal_from_v1",
                Gender = "Female",
                BirthYear = 1997
            };

            _profileRepoMock.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<HealthProfile, bool>>>()))
                .ReturnsAsync(profileInDb);

            var response = await _service.GetMyHealthProfileAsync(userId);

            // B10: Dữ liệu cũ trong DB có goal lạ phải fallback về "maintain", không làm app crash
            Assert.Equal("maintain", response.Goal);
        }

        [Fact]
        public async Task B9_CreateProfile_MissingGenderOrBirthYear_ThrowsBadRequest()
        {
            var userId = "user123";
            _profileRepoMock.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<HealthProfile, bool>>>()))
                .ReturnsAsync((HealthProfile?)null);

            var request = new UpdateHealthProfileRequest
            {
                HeightCm = 170,
                WeightKg = 60,
                Goal = "maintain",
                Gender = null, // Missing on create
                BirthYear = null
            };

            // B9: Khi tạo hồ sơ lần đầu, thiếu Gender hoặc BirthYear phải trả 400
            await Assert.ThrowsAsync<BadRequestException>(() => _service.UpdateMyHealthProfileAsync(userId, request));
        }

        [Fact]
        public async Task B9_UpdateProfile_NullGenderOrBirthYear_PreservesExistingValues()
        {
            var userId = "user123";
            var existingProfile = new HealthProfile
            {
                Id = "p1",
                UserId = userId,
                HeightCm = 170,
                WeightKg = 60,
                Goal = "maintain",
                Gender = "Female",
                BirthYear = 1997
            };

            _profileRepoMock.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<HealthProfile, bool>>>()))
                .ReturnsAsync(existingProfile);

            var request = new UpdateHealthProfileRequest
            {
                HeightCm = 172,
                WeightKg = 61,
                Goal = "maintain",
                Gender = null, // Omitting on update
                BirthYear = null
            };

            var response = await _service.UpdateMyHealthProfileAsync(userId, request);

            // B9: Khi update, không gửi Gender/BirthYear thì giữ nguyên giá trị cũ
            Assert.Equal("Female", response.Gender);
            Assert.Equal(1997, response.BirthYear);
            Assert.Equal(172, response.HeightCm);
            Assert.Equal(61, response.WeightKg);
        }

        [Fact]
        public async Task B8_UpdateProfile_SyncsDailyTargetsToCurrentWeekMealPlan()
        {
            var userId = "user123";
            var existingProfile = new HealthProfile
            {
                Id = "p1",
                UserId = userId,
                HeightCm = 170,
                WeightKg = 60,
                Goal = "maintain",
                Gender = "Female",
                BirthYear = 1997
            };

            _profileRepoMock.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<HealthProfile, bool>>>()))
                .ReturnsAsync(existingProfile);

            var currentPlan = new MealPlan
            {
                Id = "plan_current_week",
                UserId = userId,
                Goal = "maintain",
                DailyTargets = new MealPlanDailyTargets { Calories = 1800 }
            };

            _mealPlanRepoMock.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<MealPlan, bool>>>()))
                .ReturnsAsync(currentPlan);

            var request = new UpdateHealthProfileRequest
            {
                HeightCm = 170,
                WeightKg = 60,
                Goal = "lose_weight",
                Gender = "Female",
                BirthYear = 1997
            };

            var response = await _service.UpdateMyHealthProfileAsync(userId, request);

            // B8: Cập nhật MealPlan tuần hiện tại theo calo mục tiêu mới
            Assert.Equal("lose_weight", currentPlan.Goal);
            Assert.Equal(response.TargetCalories, currentPlan.DailyTargets.Calories);
            _mealPlanRepoMock.Verify(r => r.UpdateAsync(currentPlan.Id, currentPlan), Times.Once);
        }

        [Fact]
        public void B20_GetAllergens_FilteredByKeyword_ReturnsMatchingAllergens()
        {
            var result = _service.GetAllergens("peanut").ToList();

            Assert.NotEmpty(result);
            Assert.Contains(result, a => a.AllergenId == "peanut");

            var emptyResult = _service.GetAllergens("non_existent_chemical_xyz").ToList();
            Assert.Empty(emptyResult);
        }

        [Fact]
        public async Task LogMetrics_SavesWaistAndBodyFat_AndUpdatesProfile()
        {
            var userId = "user123";
            var profile = new HealthProfile
            {
                Id = "p1",
                UserId = userId,
                HeightCm = 170,
                WeightKg = 70
            };

            _profileRepoMock.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<HealthProfile, bool>>>()))
                .ReturnsAsync(profile);

            var request = new LogMetricsRequest
            {
                WeightKg = 68.5,
                WaistCm = 78.0,
                BodyFatPct = 16.5
            };

            var logResponse = await _service.LogMetricsAsync(userId, request);

            Assert.NotNull(logResponse);
            Assert.Equal(68.5, logResponse.WeightKg);
            Assert.Equal(78.0, logResponse.WaistCm);
            Assert.Equal(16.5, logResponse.BodyFatPct);
            _logRepoMock.Verify(r => r.CreateAsync(It.IsAny<HealthMetricLog>()), Times.Once);
            _profileRepoMock.Verify(r => r.UpdateAsync(profile.Id, profile), Times.Once);
        }
    }
}

