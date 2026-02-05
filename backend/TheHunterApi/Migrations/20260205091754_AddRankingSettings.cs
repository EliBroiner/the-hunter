using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

#pragma warning disable CA1814 // Prefer jagged arrays over multidimensional

namespace TheHunterApi.Migrations
{
    /// <inheritdoc />
    public partial class AddRankingSettings : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "RankingSettings",
                columns: table => new
                {
                    Key = table.Column<string>(type: "TEXT", nullable: false),
                    Value = table.Column<double>(type: "REAL", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RankingSettings", x => x.Key);
                });

            migrationBuilder.InsertData(
                table: "RankingSettings",
                columns: new[] { "Key", "Value" },
                values: new object[,]
                {
                    { "contentWeight", 120.0 },
                    { "exactPhraseBonus", 150.0 },
                    { "filenameWeight", 200.0 },
                    { "fullMatchMultiplier", 1.2 },
                    { "pathWeight", 80.0 }
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "RankingSettings");
        }
    }
}
