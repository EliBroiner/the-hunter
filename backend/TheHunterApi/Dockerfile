# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy csproj and restore dependencies
COPY ["TheHunterApi.csproj", "./"]
RUN dotnet restore

# Copy everything else and build
COPY . .
RUN dotnet publish -c Release -o /app/publish

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# העתקת הקבצים מה-build stage
COPY --from=build /app/publish .

# Cloud Run משתמש ב-PORT environment variable
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

# Entry point
ENTRYPOINT ["dotnet", "TheHunterApi.dll"]
