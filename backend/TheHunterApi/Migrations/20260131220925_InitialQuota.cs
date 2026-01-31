using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace TheHunterApi.Migrations
{
    /// <inheritdoc />
    public partial class InitialQuota : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "UserAiUsages",
                columns: table => new
                {
                    UserId = table.Column<string>(type: "TEXT", maxLength: 256, nullable: false),
                    YearMonth = table.Column<string>(type: "TEXT", maxLength: 7, nullable: false),
                    ScanCount = table.Column<int>(type: "INTEGER", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UserAiUsages", x => new { x.UserId, x.YearMonth });
                });

            migrationBuilder.CreateIndex(
                name: "IX_UserAiUsages_UserId_YearMonth",
                table: "UserAiUsages",
                columns: new[] { "UserId", "YearMonth" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "UserAiUsages");
        }
    }
}
