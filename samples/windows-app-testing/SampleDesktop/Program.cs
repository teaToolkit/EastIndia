// A desktop window with a text box, a PIN box and a Save button. Save writes the text to C:\ProgramData\EastIndiaSample\saved.txt
// and the PIN to pin.txt beside it, so that a test can check what reached the PIN box.
using System.Windows.Forms;

ApplicationConfiguration.Initialize();
var form = new Form { Text = "Sample Desktop", Width = 420, Height = 200 };
var name = new TextBox { Name = "CustomerName", AccessibleName = "Customer name", Left = 20, Top = 20, Width = 360 };
var pin = new TextBox { Name = "Pin", AccessibleName = "PIN", Left = 20, Top = 100, Width = 120, UseSystemPasswordChar = true };
var save = new Button { Name = "Save", Text = "Save", Left = 20, Top = 60, Width = 100 };
var status = new Label { Name = "Status", Text = "Not saved", Left = 140, Top = 65, Width = 240 };
save.Click += (_, _) =>
{
	var folder = Directory.CreateDirectory(@"C:\ProgramData\EastIndiaSample").FullName;
	File.WriteAllText(Path.Combine(folder, "saved.txt"), name.Text);
	File.WriteAllText(Path.Combine(folder, "pin.txt"), pin.Text);
	status.Text = "Saved: " + name.Text;
};
form.Controls.AddRange([name, pin, save, status]);
Application.Run(form);
