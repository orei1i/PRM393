using System.Collections.Generic;
using ApplicationLayer.DTOs.HealthProfile;
using ApplicationLayer.Interfaces;
using ControllerLayer.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace ControllerLayer.Controllers
{
    [Route("api/v1/catalog")]
    [ApiController]
    public class CatalogController : ControllerBase
    {
        private readonly IHealthProfileService _healthProfileService;

        public CatalogController(IHealthProfileService healthProfileService)
        {
            _healthProfileService = healthProfileService;
        }

        /// <summary>Lấy danh mục các chất dị ứng chuẩn được hệ thống hỗ trợ.</summary>
        [HttpGet("allergens")]
        [AllowAnonymous]
        [ProducesResponseType(typeof(ApiResponse<IEnumerable<AllergenResponse>>), StatusCodes.Status200OK)]
        public ActionResult<ApiResponse<IEnumerable<AllergenResponse>>> GetAllergens()
        {
            var allergens = _healthProfileService.GetAllergens();
            return Ok(ApiResponse<IEnumerable<AllergenResponse>>.Ok(allergens));
        }
    }
}

