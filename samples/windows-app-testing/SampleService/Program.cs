// A Windows service that answers GET /health on port 8080 and writes a line to C:\ProgramData\EastIndiaSample\service.log at start.
var builder = WebApplication.CreateBuilder(new WebApplicationOptions { Args = args, ContentRootPath = AppContext.BaseDirectory });
builder.Host.UseWindowsService(options => options.ServiceName = "SampleService");
builder.WebHost.UseUrls("http://0.0.0.0:8080");
var app = builder.Build();
var folder = Directory.CreateDirectory(@"C:\ProgramData\EastIndiaSample").FullName;
File.AppendAllText(Path.Combine(folder, "service.log"), $"{DateTime.UtcNow:O} SampleService started{Environment.NewLine}");
app.MapGet("/health", () => Results.Text("healthy"));
app.Run();
