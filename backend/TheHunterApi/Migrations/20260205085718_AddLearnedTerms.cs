using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace TheHunterApi.Migrations
{
    /// <inheritdoc />
    public partial class AddLearnedTerms : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "LearnedTerms",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    Term = table.Column<string>(type: "TEXT", nullable: false),
                    Category = table.Column<string>(type: "TEXT", nullable: false),
                    Frequency = table.Column<int>(type: "INTEGER", nullable: false),
                    IsApproved = table.Column<bool>(type: "INTEGER", nullable: false),
                    LastSeen = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_LearnedTerms", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_LearnedTerms_Term",
                table: "LearnedTerms",
                column: "Term");

            migrationBuilder.CreateIndex(
                name: "IX_LearnedTerms_Term_Category",
                table: "LearnedTerms",
                columns: new[] { "Term", "Category" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "LearnedTerms");
        }
    }
}
