using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;

class Program
{
    const string BASE_URL = "https://dashboard.minet.vn";

    static async Task<int> Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine();
        Console.WriteLine("===== Minet Mining Setup =====");
        Console.WriteLine();
        Console.ResetColor();

        Console.Write("Email: ");
        string? email = Console.ReadLine()?.Trim();
        if (string.IsNullOrEmpty(email))
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("Email required.");
            Console.ResetColor();
            return 1;
        }

        Console.WriteLine("Preparing...");

        using var http = new HttpClient();
        http.DefaultRequestHeaders.Add("User-Agent", "MinetSetup/1.0");
        http.Timeout = TimeSpan.FromSeconds(30);

        string ip;
        try { ip = (await http.GetStringAsync("https://api.ipify.org")).Trim(); }
        catch
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("Network error.");
            Console.ResetColor();
            return 1;
        }

        string encodedEmail = Uri.EscapeDataString(email);
        string encodedIp    = Uri.EscapeDataString(ip);
        string setupUrl     = $"{BASE_URL}/api/minecoin/setup?email={encodedEmail}&ip={encodedIp}&mode=dashboard";

        string scriptContent;
        try
        {
            Console.WriteLine("Fetching setup script...");
            scriptContent = await http.GetStringAsync(setupUrl);
        }
        catch (Exception ex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"Failed: {ex.Message}");
            Console.ResetColor();
            return 1;
        }

        string tmpScript = Path.Combine(Path.GetTempPath(), "minet_setup.sh");
        await File.WriteAllTextAsync(tmpScript, scriptContent);

        string[] bashCandidates = {
            @"C:\Program Files\Git\bin\bash.exe",
            @"C:\Program Files (x86)\Git\bin\bash.exe",
        };

        string? bashPath = null;
        foreach (var c in bashCandidates)
            if (File.Exists(c)) { bashPath = c; break; }

        if (bashPath == null)
        {
            try
            {
                var p = Process.Start(new ProcessStartInfo {
                    FileName = "bash.exe", Arguments = "--version",
                    RedirectStandardOutput = true, RedirectStandardError = true,
                    UseShellExecute = false, CreateNoWindow = true
                });
                p?.WaitForExit(3000);
                if (p?.ExitCode == 0) bashPath = "bash.exe";
            }
            catch { }
        }

        if (bashPath == null)
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine("\n[ERROR] Khong tim thay bash tren may.");
            Console.WriteLine("Cai Git for Windows: https://git-scm.com/download/win");
            Console.WriteLine("Hoac WSL: chay 'wsl --install' trong CMD");
            Console.ResetColor();
            Console.WriteLine("\nNhan phim bat ky de thoat...");
            Console.ReadKey();
            return 1;
        }

        Console.WriteLine("Running setup...\n");

        var proc = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName  = bashPath,
                Arguments = $"\"{tmpScript}\"",
                UseShellExecute = false,
                CreateNoWindow  = false
            }
        };

        proc.Start();
        proc.WaitForExit();

        Console.WriteLine();
        if (proc.ExitCode == 0)
        {
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("Setup completed successfully!");
        }
        else
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"Setup exited with code {proc.ExitCode}.");
        }
        Console.ResetColor();
        Console.WriteLine("\nNhan phim bat ky de thoat...");
        Console.ReadKey();
        return proc.ExitCode;
    }
}
