using Microsoft.AspNetCore.Mvc;
using TheHunterApi.Filters;
using TheHunterApi.Models;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

/// <summary>
/// API להגדרות סריקה — גישה מ-Admin Portal. שינויים מיושמים מיד.
/// </summary>
[Route("admin")]
[ServiceFilter(typeof(AdminKeyAuthorizationFilter))]
[ApiController]
public class ScannerSettingsController : ControllerBase
{
    private readonly IScannerSettingsService _scannerSettings;
    private readonly ILogger<ScannerSettingsController> _logger;

    public ScannerSettingsController(IScannerSettingsService scannerSettings, ILogger<ScannerSettingsController> logger)
    {
        _scannerSettings = scannerSettings;
        _logger = logger;
    }

    /// <summary>GET /admin/scanner-settings — מחזיר את כל ההגדרות + metadata (editable / source).</summary>
    [HttpGet("scanner-settings")]
    [ProducesResponseType(typeof(ScannerSettingsGetResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> Get()
    {
        try
        {
            return Ok(new ScannerSettingsGetResponse
            {
                GarbageThresholdPercent = new ScannerSettingItem(await _scannerSettings.GetGarbageThresholdPercentAsync(), true, "firestore"),
                MinMeaningfulLength = new ScannerSettingItem(await _scannerSettings.GetMinMeaningfulLengthAsync(), true, "firestore"),
                MinValidCharRatioPercent = new ScannerSettingItem(await _scannerSettings.GetMinValidCharRatioPercentAsync(), true, "firestore"),
                CloudVisionFallbackEnabled = new ScannerSettingItem(await _scannerSettings.GetCloudVisionFallbackEnabledAsync() ? 1.0 : 0.0, true, "firestore")
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Get scanner-settings failed");
            return StatusCode(500, new { error = ex.Message, details = ex.InnerException?.Message });
        }
    }

    /// <summary>POST /admin/scanner-settings — עדכון הגדרות (JSON).</summary>
    [HttpPost("scanner-settings")]
    [Consumes("application/json")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> Update([FromBody] ScannerSettingsDto dto)
    {
        if (dto == null)
            return BadRequest(new ErrorResponse { Error = "Body required" });

        try
        {
            if (dto.GarbageThresholdPercent.HasValue)
            {
                await _scannerSettings.SetGarbageThresholdPercentAsync(dto.GarbageThresholdPercent.Value);
                _logger.LogInformation("Scanner: garbageThresholdPercent = {Value}", dto.GarbageThresholdPercent.Value);
            }
            if (dto.MinMeaningfulLength.HasValue)
            {
                await _scannerSettings.SetMinMeaningfulLengthAsync(dto.MinMeaningfulLength.Value);
                _logger.LogInformation("Scanner: minMeaningfulLength = {Value}", dto.MinMeaningfulLength.Value);
            }
            if (dto.MinValidCharRatioPercent.HasValue)
            {
                await _scannerSettings.SetMinValidCharRatioPercentAsync(dto.MinValidCharRatioPercent.Value);
                _logger.LogInformation("Scanner: minValidCharRatioPercent = {Value}", dto.MinValidCharRatioPercent.Value);
            }
            if (dto.CloudVisionFallbackEnabled.HasValue)
            {
                await _scannerSettings.SetCloudVisionFallbackEnabledAsync(dto.CloudVisionFallbackEnabled.Value);
                _logger.LogInformation("Scanner: cloudVisionFallbackEnabled = {Value}", dto.CloudVisionFallbackEnabled.Value);
            }

            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "POST scanner-settings failed");
            return StatusCode(500, new { error = ex.Message, details = ex.InnerException?.Message });
        }
    }
}
