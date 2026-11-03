using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace ApplicationLayer.DTOs.Content
{
    /// <summary>"id" là id hồ sơ, dùng cho POST /bookings. Danh sách bỏ bio và certificates.</summary>
    public class ChefResponse
    {
        public string Id { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public string FullName { get; set; } = string.Empty;
        public string Headline { get; set; } = string.Empty;
        public string Specialty { get; set; } = string.Empty;
        public double Rating { get; set; }
        public int ReviewCount { get; set; }
        public int YearsExperience { get; set; }
        public string City { get; set; } = string.Empty;
        public int ConsultCount { get; set; }
        public long PricePerDay { get; set; }
        public long FeedbackPricePerDay { get; set; }
        public int MinPlanDays { get; set; }
        public int MaxPlanDays { get; set; }
        public bool AcceptingBookings { get; set; }

        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? Bio { get; set; }

        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public List<string>? Certificates { get; set; }
    }

    public class ChefProfileResponse
    {
        public string Id { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public string Specialty { get; set; } = string.Empty;
        public string Bio { get; set; } = string.Empty;
        public long PricePerDay { get; set; }
        public long FeedbackPricePerDay { get; set; }
        public int MinPlanDays { get; set; }
        public int MaxPlanDays { get; set; }
        public bool AcceptingBookings { get; set; }
    }

    public class SaveChefProfileRequest
    {
        public string? Specialty { get; set; }
        public string? Bio { get; set; }
        public long? PricePerDay { get; set; }
        public long? FeedbackPricePerDay { get; set; }
        public int? MinPlanDays { get; set; }
        public int? MaxPlanDays { get; set; }
        public bool? AcceptingBookings { get; set; }
    }

    public class SubmitChefApplicationRequest
    {
        public List<string>? Specialties { get; set; }
        public int? YearsExperience { get; set; }
        public string? City { get; set; }
        public string? Bio { get; set; }
        public List<string>? Certificates { get; set; }
    }

    public class ChefApplicationStatusResponse
    {
        /// <summary>none | pending | approved | rejected</summary>
        public string Status { get; set; } = "none";
        public string? RejectReason { get; set; }
    }

    public class ChefCertificateResponse
    {
        public string Name { get; set; } = string.Empty;
        public string? FileUrl { get; set; }
    }

    public class ChefApplicationResponse
    {
        public string Id { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public string FullName { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
        public string City { get; set; } = string.Empty;
        public List<string> Specialties { get; set; } = new();
        public int YearsExperience { get; set; }
        public string Bio { get; set; } = string.Empty;
        public List<ChefCertificateResponse> Certificates { get; set; } = new();
        public DateTime? MemberSince { get; set; }
        public long PostCount { get; set; }
        public DateTime SubmittedAt { get; set; }
        public string Status { get; set; } = string.Empty;
        public string? ReviewNote { get; set; }
        public string? ReviewedBy { get; set; }
        public DateTime? ReviewedAt { get; set; }
    }

    public class ReviewChefApplicationRequest
    {
        public string? Decision { get; set; }
        public string? Note { get; set; }
    }
}
