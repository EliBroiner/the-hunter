using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace TheHunterApi.Migrations
{
    /// <inheritdoc />
    public partial class AddAppManagedUsers : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "AppManagedUsers",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    UserId = table.Column<string>(type: "TEXT", maxLength: 256, nullable: false),
                    Email = table.Column<string>(type: "TEXT", maxLength: 256, nullable: false),
                    DisplayName = table.Column<string>(type: "TEXT", maxLength: 256, nullable: true),
                    Role = table.Column<string>(type: "TEXT", maxLength: 64, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AppManagedUsers", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_AppManagedUsers_Email",
                table: "AppManagedUsers",
                column: "Email");

            migrationBuilder.CreateIndex(
                name: "IX_AppManagedUsers_UserId",
                table: "AppManagedUsers",
                column: "UserId",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "AppManagedUsers");
        }
    }
}
