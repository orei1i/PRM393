using System;

namespace DomainLayer.Helpers
{
    public static class EnergyCalculator
    {
        public static double CalculateBmi(double heightCm, double weightKg)
        {
            if (heightCm <= 0 || weightKg <= 0) return 0;
            var meters = heightCm / 100.0;
            return Math.Round(weightKg / (meters * meters), 1);
        }

        public static string CategorizeBmi(double bmi, bool useAsiaPacific = true)
        {
            if (useAsiaPacific)
            {
                if (bmi < 18.5) return "underweight";
                if (bmi < 23.0) return "normal";
                if (bmi < 25.0) return "overweight";
                return "obese";
            }
            else
            {
                if (bmi < 18.5) return "underweight";
                if (bmi < 25.0) return "normal";
                if (bmi < 30.0) return "overweight";
                return "obese";
            }
        }

        public static double CalculateBmr(string? gender, double weightKg, double heightCm, int age)
        {
            var g = (gender ?? "Other").Trim().ToLowerInvariant();
            double s = g switch
            {
                "male" or "nam" => 5.0,
                "female" or "nữ" or "nu" => -161.0,
                _ => -78.0 // Mean of male and female
            };

            return 10.0 * weightKg + 6.25 * heightCm - 5.0 * age + s;
        }

        public static double GetActivityFactor(string? activityLevel)
        {
            var a = (activityLevel ?? "light").Trim().ToLowerInvariant();
            return a switch
            {
                "sedentary" or "ít" or "it" => 1.2,
                "light" or "nhẹ" or "nhe" => 1.375,
                "moderate" or "vừa" or "vua" => 1.55,
                "active" or "nhiều" or "nhieu" => 1.725,
                _ => 1.375
            };
        }

        public static double GetGoalAdjustment(string? goal)
        {
            var g = (goal ?? "maintain").Trim().ToLowerInvariant();
            return g switch
            {
                "lose" or "giảm cân" or "giam_can" => -0.15,
                "maintain" or "giữ cân" or "giu_can" => 0.0,
                "muscle" or "lean_muscle" or "tăng cơ" or "tang_co" => 0.05,
                "gain" or "tăng cân" or "tang_can" => 0.10,
                _ => 0.0
            };
        }

        public static int RoundToDisplayCalories(double kcal)
        {
            return (int)Math.Round(kcal / 10.0) * 10;
        }

        public static (double Bmr, double Tdee, int TargetCalories, double Bmi, string BmiCategory) ComputeAll(
            string? gender,
            int birthYear,
            double heightCm,
            double weightKg,
            string? activityLevel,
            string? goal)
        {
            var currentYear = DateTime.UtcNow.Year;
            var age = Math.Clamp(currentYear - birthYear, 13, 100);

            var bmi = CalculateBmi(heightCm, weightKg);
            var bmiCategory = CategorizeBmi(bmi, useAsiaPacific: true);

            var bmr = Math.Round(CalculateBmr(gender, weightKg, heightCm, age), 1);
            var factor = GetActivityFactor(activityLevel);
            var tdee = Math.Round(bmr * factor, 1);

            var goalAdjustment = GetGoalAdjustment(goal);
            var targetCalories = RoundToDisplayCalories(tdee * (1.0 + goalAdjustment));

            return (bmr, tdee, targetCalories, bmi, bmiCategory);
        }
    }
}

