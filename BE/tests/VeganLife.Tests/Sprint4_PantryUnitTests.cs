using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using ApplicationLayer.DTOs.Pantry;
using ApplicationLayer.Services;
using DomainLayer.Entities;
using DomainLayer.Helpers;
using DomainLayer.Interfaces;
using Moq;
using Xunit;

namespace VeganLife.Tests
{
    public class Sprint4_PantryUnitTests
    {
        [Theory]
        [InlineData("Cà chua", true)]
        [InlineData("Cà rốt", true)]
        [InlineData("Sữa đậu nành", true)]
        [InlineData("Nấm đùi gà", true)]
        [InlineData("Bơ đậu phộng", true)]
        [InlineData("Yến mạch", true)]
        [InlineData("Bò lúc lắc chay", true)]
        [InlineData("Chả lụa chay", true)]
        [InlineData("Bơ thực vật", true)]
        [InlineData("Thịt bò", false)]
        [InlineData("Thịt gà", false)]
        [InlineData("Trứng gà", false)]
        [InlineData("Cá hồi", false)]
        [InlineData("Sữa bò tươi", false)]
        [InlineData("Bơ lạt", false)]
        [InlineData("Nước mắm cá cơm", false)]
        [InlineData("Pate gan", false)]
        public void B13_VeganClassifier_ClassifiesAccurately(string ingredientName, bool expectedIsVegan)
        {
            var isVegan = VeganClassifier.ClassifyIsVegan(ingredientName);
            Assert.Equal(expectedIsVegan, isVegan);
        }

        [Fact]
        public async Task B14_AllergyWarning_TriggersWhenStandardAllergenMatches()
        {
            var userId = "user_allergy_test";
            var mockPantryRepo = new Mock<IGenericRepository<PantryItem>>();
            var mockIngRepo = new Mock<IGenericRepository<Ingredient>>();
            var mockProfileRepo = new Mock<IGenericRepository<HealthProfile>>();

            // User has standard allergy "peanut"
            mockProfileRepo.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<HealthProfile, bool>>>()))
                .ReturnsAsync(new HealthProfile
                {
                    UserId = userId,
                    Allergies = new List<string> { "peanut" }
                });

            // Ingredient in catalog has allergen "peanut"
            mockIngRepo.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<Ingredient, bool>>>()))
                .ReturnsAsync(new Ingredient
                {
                    Id = "ing_peanut_1",
                    Name = "Đậu phộng",
                    NormalizedName = "dau phong",
                    IsVegan = true,
                    Allergens = new List<string> { "peanut" }
                });

            var savedItems = new List<PantryItem>();
            mockPantryRepo.Setup(r => r.FindAsync(It.IsAny<Expression<Func<PantryItem, bool>>>()))
                .ReturnsAsync(savedItems);
            mockPantryRepo.Setup(r => r.CreateAsync(It.IsAny<PantryItem>()))
                .Callback<PantryItem>(item => savedItems.Add(item))
                .ReturnsAsync((PantryItem item) => item);

            var service = new PantryService(mockPantryRepo.Object, mockIngRepo.Object, mockProfileRepo.Object);

            var response = await service.AddPantryItemAsync(userId, new AddPantryItemRequest
            {
                Ingredient = "Đậu phộng",
                Quantity = 1
            });

            Assert.NotNull(response.AllergyWarning);
            Assert.Contains("peanut", response.AllergyWarning, StringComparison.OrdinalIgnoreCase);
        }

        [Fact]
        public async Task B34_ScanningAgain_UpsertsAndDoesNotDoubleQuantity()
        {
            var userId = "user_pantry_b34";
            var mockPantryRepo = new Mock<IGenericRepository<PantryItem>>();
            var mockIngRepo = new Mock<IGenericRepository<Ingredient>>();
            var mockProfileRepo = new Mock<IGenericRepository<HealthProfile>>();

            mockProfileRepo.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<HealthProfile, bool>>>()))
                .ReturnsAsync(new HealthProfile { UserId = userId, Allergies = new List<string>() });

            mockIngRepo.Setup(r => r.FirstOrDefaultAsync(It.IsAny<Expression<Func<Ingredient, bool>>>()))
                .ReturnsAsync((Ingredient?)null);

            var pantryDatabase = new List<PantryItem>();

            mockPantryRepo.Setup(r => r.FindAsync(It.IsAny<Expression<Func<PantryItem, bool>>>()))
                .ReturnsAsync((Expression<Func<PantryItem, bool>> predicate) => pantryDatabase.AsQueryable().Where(predicate).ToList());

            mockPantryRepo.Setup(r => r.CreateAsync(It.IsAny<PantryItem>()))
                .Callback<PantryItem>(item =>
                {
                    item.Id = Guid.NewGuid().ToString();
                    pantryDatabase.Add(item);
                })
                .ReturnsAsync((PantryItem item) => item);

            mockPantryRepo.Setup(r => r.UpdateAsync(It.IsAny<string>(), It.IsAny<PantryItem>()))
                .Callback<string, PantryItem>((id, updated) =>
                {
                    var idx = pantryDatabase.FindIndex(x => x.Id == id);
                    if (idx >= 0) pantryDatabase[idx] = updated;
                })
                .Returns(Task.CompletedTask);

            var service = new PantryService(mockPantryRepo.Object, mockIngRepo.Object, mockProfileRepo.Object);

            // First scan: 2.0 items
            var firstScan = await service.AddPantryItemAsync(userId, new AddPantryItemRequest
            {
                Ingredient = "Cà chua",
                Quantity = 2.0,
                Unit = "quả",
                ScannedAt = DateTime.UtcNow
            });

            Assert.Equal(2.0, firstScan.Quantity);
            Assert.Single(pantryDatabase);

            // Second scan: still 2.0 items (confirming presence in fridge)
            var secondScan = await service.AddPantryItemAsync(userId, new AddPantryItemRequest
            {
                Ingredient = "Cà chua",
                Quantity = 2.0,
                Unit = "quả",
                ScannedAt = DateTime.UtcNow
            });

            // B34 fix: Quantity remains 2.0, does not double to 4.0!
            Assert.Equal(2.0, secondScan.Quantity);
            Assert.Single(pantryDatabase);
            Assert.Equal("ca chua", pantryDatabase[0].NormalizedName);
        }
    }
}
