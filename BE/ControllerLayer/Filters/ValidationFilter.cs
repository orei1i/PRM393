using ControllerLayer.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace ControllerLayer.Filters
{
    /// <summary>
    /// Filter tự động validate ModelState trước khi vào Action.
    /// Trả về ApiResponse 400 khi request data không hợp lệ — Flutter nhận message rõ ràng.
    /// </summary>
    public class ValidationFilter : IActionFilter
    {
        public void OnActionExecuting(ActionExecutingContext context)
        {
            if (!context.ModelState.IsValid)
            {
                var errors = context.ModelState
                    .Where(x => x.Value?.Errors.Count > 0)
                    .SelectMany(x => x.Value!.Errors)
                    .Select(e => e.ErrorMessage)
                    .ToList();

                var message = string.Join(" | ", errors);

                var response = ApiResponse<object>.Fail(message, 400);

                context.Result = new BadRequestObjectResult(response);
            }
        }

        public void OnActionExecuted(ActionExecutedContext context) { }
    }
}
