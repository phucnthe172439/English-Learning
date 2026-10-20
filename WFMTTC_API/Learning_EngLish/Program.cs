using Learning_EngLish.Data;
using Learning_EngLish.Repositories;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOpenApi();

// ADO.NET data access: one connection factory for the whole app,
// one repository per request (Scoped).
builder.Services.AddSingleton<SqlConnectionFactory>();
builder.Services.AddScoped<VocabularyRepository>();
builder.Services.AddScoped<TopicRepository>();
builder.Services.AddScoped<WordTypeRepository>();

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

app.Run();
