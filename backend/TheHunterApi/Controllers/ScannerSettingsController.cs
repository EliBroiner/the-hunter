using Microsoft.AspNetCore.Mvc;
using TheHunterApi.Filters;
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
    public async Task<IActionResult> Get()
    {
        return Ok(new ScannerSettingsGetResponse
        {
            GarbageThresholdPercent = new ScannerSettingItem(await _scannerSettings.GetGarbageThresholdPercentAsync(), true, "firestore"),
            MinMeaningfulLength = new ScannerSettingItem(await _scannerSettings.GetMinMeaningfulLengthAsync(), true, "firestore"),
            MinValidCharRatioPercent = new ScannerSettingItem(await _scannerSettings.GetMinValidCharRatioPercentAsync(), true, "firestore"),
            CloudVisionFallbackEnabled = new ScannerSettingItem(await _scannerSettings.GetCloudVisionFallbackEnabledAsync() ? 1.0 : 0.0, true, "firestore")
        });
    }

    /// <summary>POST /admin/scanner-settings — עדכון הגדרות.</summary>
    [HttpPost("scanner-settings")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Update([FromBody] ScannerSettingsDto dto)
    {
        if (dto == null)
            return BadRequest(new ErrorResponse { Error = "Body required" });

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
}

public class ScannerSettingsDto
{
    public double? GarbageThresholdPercent { get; set; }
    public int? MinMeaningfulLength { get; set; }
    public double? MinValidCharRatioPercent { get; set; }
    public bool? CloudVisionFallbackEnabled { get; set; }
}

/// <summary>תשובת GET — כולל metadata לכל פרמטר (עריכה / מקור).</summary>
public class ScannerSettingsGetResponse
{
    public required ScannerSettingItem GarbageThresholdPercent { get; set; }
    public required ScannerSettingItem MinMeaningfulLength { get; set; }
    public required ScannerSettingItem MinValidCharRatioPercent { get; set; }
    public required ScannerSettingItem CloudVisionFallbackEnabled { get; set; }
}

public record ScannerSettingItem(double Value, bool Editable, string Source);
