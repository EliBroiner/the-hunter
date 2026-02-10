using Microsoft.AspNetCore.Mvc;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

[ApiController]
[Route("api/users")]
public class UsersController : ControllerBase
{
    private readonly UserRoleService _userRoleService;
    private readonly AdminFirestoreService _adminFirestore;

    public UsersController(UserRoleService userRoleService, AdminFirestoreService adminFirestore)
    {
        _userRoleService = userRoleService;
        _adminFirestore = adminFirestore;
    }

    /// <summary>
    /// בודק אם למשתמש יש תפקיד מסוים. העברת email מאפשרת Auto-Bootstrap Admin (ADMIN_EMAIL).
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

    /// <summary>
    /// מיגרציה חד-פעמית: מוסיף שדה id לכל מסמך ב-users שחסר בו (id = Document ID). להרצה מהדיבאגר.
    /// </summary>
    [HttpPost("migrate-ensure-id")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> MigrateEnsureId()
    {
        try
        {
            var (total, updated) = await _adminFirestore.MigrateUsersEnsureIdFieldAsync();
            return Ok(new { total, updated, message = $"Users: {total} total, {updated} documents updated with id field." });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { error = ex.Message });
        }
    }
}

public class CheckRoleResponse
{
    public bool HasRole { get; set; }
}
