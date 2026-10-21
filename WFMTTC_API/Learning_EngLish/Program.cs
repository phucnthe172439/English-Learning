using Learning_EngLish.Data;
using Learning_EngLish.Repositories;
using Microsoft.AspNetCore.HttpLogging;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOpenApi();

// ADO.NET data access: one connection factory for the whole app,
// one repository per request (Scoped).
builder.Services.AddSingleton<SqlConnectionFactory>();
builder.Services.AddScoped<VocabularyRepository>();
builder.Services.AddScoped<TopicRepository>();
builder.Services.AddScoped<WordTypeRepository>();

// GET /health: 200 "Healthy" when SQL Server answers, 503 "Unhealthy" when it doesn't.
builder.Services.AddHealthChecks()
    .AddCheck<DatabaseHealthCheck>("database");

// One log line per request: method, path, status code, duration.
// No headers or bodies, so nothing sensitive ends up in the logs.
builder.Services.AddHttpLogging(options =>
{
    options.LoggingFields = HttpLoggingFields.RequestMethod
                          | HttpLoggingFields.RequestPath
                          | HttpLoggingFields.ResponseStatusCode
                          | HttpLoggingFields.Duration;
    options.CombineLogs = true;
});

// Allow the Angular app to call this API from the browser:
// 4200 = ng serve (local dev), 4000 = frontend Docker container.

builder.Services.AddCors(options =>
{
    options.AddPolicy("Frontend", policy => policy
        .WithOrigins("http://localhost:4200", "http://localhost:4000")
        .AllowAnyHeader()
        .AllowAnyMethod());
});

var app = builder.Build();

// First in the pipeline, so the duration covers everything after it.
app.UseHttpLogging();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();

    // use swagger instead of seperate api
    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/openapi/v1.json", "Learning English API");
    });
}

app.UseHttpsRedirection();

app.UseCors("Frontend");

app.UseAuthorization();

app.MapControllers();

// Not request-logged: platforms call /health every few seconds. Failures are still logged by the health check itself.
app.MapHealthChecks("/health").WithHttpLogging(HttpLoggingFields.None);

app.Run();
