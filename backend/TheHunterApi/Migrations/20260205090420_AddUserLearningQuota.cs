using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace TheHunterApi.Migrations
{
    /// <inheritdoc />
    public partial class AddUserLearningQuota : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "UserLearningQuotas",
                columns: table => new
                {
                    UserId = table.Column<string>(type: "TEXT", maxLength: 256, nullable: false),
                    DateKey = table.Column<string>(type: "TEXT", maxLength: 10, nullable: false),
                    SuggestionCount = table.Column<int>(type: "INTEGER", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UserLearningQuotas", x => new { x.UserId, x.DateKey });
                });

            migrationBuilder.CreateIndex(
                name: "IX_UserLearningQuotas_UserId_DateKey",
                table: "UserLearningQuotas",
                columns: new[] { "UserId", "DateKey" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "UserLearningQuotas");
        }
    }
}
