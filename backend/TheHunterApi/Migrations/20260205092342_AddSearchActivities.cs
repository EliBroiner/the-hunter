using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace TheHunterApi.Migrations
{
    /// <inheritdoc />
    public partial class AddSearchActivities : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "SearchActivities",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    Term = table.Column<string>(type: "TEXT", nullable: false),
                    Count = table.Column<int>(type: "INTEGER", nullable: false),
                    LastSearch = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SearchActivities", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_SearchActivities_Term",
                table: "SearchActivities",
                column: "Term",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "SearchActivities");
        }
    }
}
