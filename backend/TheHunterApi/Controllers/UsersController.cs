using Microsoft.AspNetCore.Mvc;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

[ApiController]
[Route("api/users")]
public class UsersController : ControllerBase
{
    private readonly UserRoleService _userRoleService;

    public UsersController(UserRoleService userRoleService)
    {
        _userRoleService = userRoleService;
    }

    /// <summary>
    /// בודק אם למשתמש יש תפקיד מסוים — לצורך הצגת Debug Token וכדומה
    /// </summary>
    [HttpGet("check-role")]
    [ProducesResponseType(typeof(CheckRoleResponse), StatusCodes.Status200OK)]
    public async Task<IActionResult> CheckRole(
        [FromQuery] string userId,
        [FromQuery] string role,
        [FromQuery] string? email = null)
    {
        if (string.IsNullOrWhiteSpace(userId) && string.IsNullOrWhiteSpace(email))
            return BadRequest(new { error = "userId or email required" });
        if (string.IsNullOrWhiteSpace(role))
            return BadRequest(new { error = "role required" });

        var hasRole = await _userRoleService.HasRoleAsync(userId ?? "", role, email);
        return Ok(new CheckRoleResponse { HasRole = hasRole });
    }
}

public class CheckRoleResponse
{
    public bool HasRole { get; set; }
}
