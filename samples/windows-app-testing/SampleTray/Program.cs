// A notification-area (tray) app with no window. It writes the time to C:\ProgramData\EastIndiaSample\tray.txt every 5 seconds,
// so a test can see that it is alive, and its menu's Exit item ends it.
using System.Windows.Forms;

ApplicationConfiguration.Initialize();
var menu = new ContextMenuStrip();
var icon = new NotifyIcon { Icon = System.Drawing.SystemIcons.Information, Text = "Sample Tray", Visible = true, ContextMenuStrip = menu };
menu.Items.Add("Exit", null, (_, _) => { icon.Visible = false; Application.Exit(); });
var folder = Directory.CreateDirectory(@"C:\ProgramData\EastIndiaSample").FullName;
var timer = new System.Windows.Forms.Timer { Interval = 5000 };
timer.Tick += (_, _) => File.WriteAllText(Path.Combine(folder, "tray.txt"), DateTime.UtcNow.ToString("O"));
timer.Start();
File.WriteAllText(Path.Combine(folder, "tray.txt"), DateTime.UtcNow.ToString("O"));
Application.Run();
