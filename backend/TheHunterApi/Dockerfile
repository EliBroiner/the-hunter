# Build stage
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Copy csproj and restore dependencies
COPY ["TheHunterApi.csproj", "./"]
RUN dotnet restore

# Copy everything else and build
COPY . .
RUN dotnet publish -c Release -o /app/publish

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app

# יצירת משתמש non-root לאבטחה
RUN adduser --disabled-password --gecos "" appuser && chown -R appuser /app
USER appuser

# העתקת הקבצים מה-build stage
COPY --from=build /app/publish .

# Cloud Run משתמש ב-PORT environment variable
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Entry point
ENTRYPOINT ["dotnet", "TheHunterApi.dll"]
