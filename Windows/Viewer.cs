using System;
using System.Linq;
using System.Diagnostics;
using System.Threading;
using System.Security.Principal;
using System.Runtime.InteropServices;
using System.Reflection;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;
using Forms = System.Windows.Forms;

[assembly: AssemblyTitle("Battery % Viewer")]
[assembly: AssemblyProduct("Battery % Viewer")]
[assembly: AssemblyVersion("10.0.0.0")]

internal sealed class Viewer
{
    private const string Prefs = @"HKEY_CURRENT_USER\Software\Varun Manoj Kumar\Battery Viewer";
    private const double MinPercentageSize = 48;
    private const double MaxPercentageSize = 180;
    private const int MinLowThreshold = 1, MaxLowThreshold = 100, DefaultLowThreshold = 20;
    private static readonly string[] Themes = { "System", "Light", "Dark" };
    private readonly Window window = Load<Window>("Dashboard");
    private readonly Speech speech = new Speech();
    private readonly DispatcherTimer timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
    private Forms.NotifyIcon trayIcon;
    private bool runInBackground = Get("RunInBackground", "0") == "1";
    private bool quitting;
    private Reading reading;
    private readonly TextBlock level, status;
    private readonly UniformGrid gauge;
    private double size = LoadPercentageSize();
    private string theme = Get("Theme", "System"), voice = Get("Voice", "");
    private bool announcePower = Get("Power", "0") == "1", announceLow = Get("Low", "0") == "1";
    private int lowThreshold = LoadLowThreshold();

    private static T Load<T>(string name)
    {
        using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name + ".xaml"))
            return (T)XamlReader.Load(stream);
    }

    private static string Get(string key, string fallback)
    {
        return Registry.GetValue(Prefs, key, fallback) as string ?? fallback;
    }

    private static void Save(string key, string value) { Registry.SetValue(Prefs, key, value); }

    private static int LoadLowThreshold()
    {
        int percent;
        return Int32.TryParse(Get("LowBatteryThreshold", ""), out percent)
            ? Math.Min(MaxLowThreshold, Math.Max(MinLowThreshold, percent))
            : DefaultLowThreshold;
    }

    private static double LoadPercentageSize()
    {
        int points;
        if (Int32.TryParse(Get("PercentageFontSize", ""), out points))
            return Math.Min(MaxPercentageSize, Math.Max(MinPercentageSize, points));
        switch (Get("Size", "Extra large"))
        {
            case "Large": return 69;
            case "Maximum": return 129;
            default: return 99;
        }
    }

    [STAThread]
    public static void Main()
    {
        string key = @"Local\BatteryPercentViewer." + WindowsIdentity.GetCurrent().User.Value;
        bool first;
        // Create the wake-up event first so a second launch during startup is remembered.
        using (var reopen = new EventWaitHandle(false, EventResetMode.AutoReset, key + ".Reopen"))
        using (var instance = new Mutex(false, key, out first))
        {
            if (!first)
            {
                var self = Process.GetCurrentProcess();
                foreach (var other in Process.GetProcessesByName(self.ProcessName))
                {
                    using (other)
                    {
                        if (other.Id != self.Id && other.SessionId == self.SessionId)
                            AllowSetForegroundWindow(other.Id);
                    }
                }
                reopen.Set();
                return;
            }
            var app = new Application();
            app.Resources.MergedDictionaries.Add(Load<ResourceDictionary>("Styles"));
            var viewer = new Viewer();
            using (var quit = new EventWaitHandle(false, EventResetMode.AutoReset, key + ".Quit"))
            {
                var wait = ThreadPool.RegisterWaitForSingleObject(reopen, (s, timedOut) =>
                    app.Dispatcher.BeginInvoke(new Action(viewer.ActivateWindow)), null, Timeout.Infinite, false);
                var quitWait = ThreadPool.RegisterWaitForSingleObject(quit, (s, timedOut) =>
                    app.Dispatcher.BeginInvoke(new Action(viewer.Quit)), null, Timeout.Infinite, true);
                try { app.Run(viewer.window); }
                finally { wait.Unregister(null); quitWait.Unregister(null); }
            }
        }
    }

    [DllImport("user32.dll")]
    private static extern bool AllowSetForegroundWindow(int processId);

    private void ActivateWindow()
    {
        if (!window.IsVisible) window.Show();
        if (window.WindowState == WindowState.Minimized) window.WindowState = WindowState.Normal;
        var target = window.OwnedWindows.Cast<Window>().LastOrDefault(w => w.IsVisible) ?? window;
        target.Activate();
    }

    private void Quit()
    {
        quitting = true;
        Application.Current.Shutdown();
    }

    private void UpdateTrayIcon()
    {
        if (!runInBackground)
        {
            RemoveTrayIcon();
            return;
        }
        if (trayIcon != null) return;
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("&Open Battery % Viewer", null, (s, e) => ActivateWindow());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Speak battery &level", null, (s, e) => {
            Refresh(false);
            speech.Say(reading.LevelDescription, voice);
        });
        menu.Items.Add("Speak &charging status", null, (s, e) => Say(true));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("&Quit Battery % Viewer", null, (s, e) => Quit());

        trayIcon = new Forms.NotifyIcon {
            Icon = System.Drawing.Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location)
                ?? (System.Drawing.Icon)System.Drawing.SystemIcons.Application.Clone(),
            Text = "Battery % Viewer",
            ContextMenuStrip = menu,
            Visible = true
        };
        trayIcon.MouseDoubleClick += (s, e) => { if (e.Button == Forms.MouseButtons.Left) ActivateWindow(); };
    }

    private void RemoveTrayIcon()
    {
        if (trayIcon == null) return;
        trayIcon.Visible = false;
        trayIcon.ContextMenuStrip.Dispose();
        trayIcon.Icon.Dispose();
        trayIcon.Dispose();
        trayIcon = null;
    }

    private Viewer()
    {
        level = (TextBlock)window.FindName("Level");
        status = (TextBlock)window.FindName("Status");
        gauge = (UniformGrid)window.FindName("Gauge");
        for (int i = 0; i < 20; i++)
            gauge.Children.Add(new Border { CornerRadius = new CornerRadius(2), Margin = new Thickness(0, 0, 3, 0) });
        var speak = (Button)window.FindName("Speak");
        var settings = (Button)window.FindName("Settings");
        speak.Click += (s, e) => Say(false);
        settings.Click += (s, e) => OpenSettings();
        ((MenuItem)window.FindName("AdjustSize")).Click += (s, e) => OpenSettings();
        ((MenuItem)window.FindName("Quit")).Click += (s, e) => Quit();
        speak.ToolTip = "Speak battery level and power status (Ctrl+S)";
        settings.ToolTip = "Display and speech settings (Ctrl+,)";
        window.PreviewKeyDown += Shortcuts;
        window.Loaded += (s, e) => speak.Focus();
        speech.Failed += message => window.Dispatcher.BeginInvoke(new Action(() => {
            if (window.IsVisible) MessageBox.Show(message, "Battery speech", MessageBoxButton.OK, MessageBoxImage.Information);
        }));
        SystemParameters.StaticPropertyChanged += SystemAppearanceChanged;
        SystemEvents.UserPreferenceChanged += UserPreferenceChanged;
        window.Closing += (s, e) => {
            if (!runInBackground || quitting) return;
            e.Cancel = true;
            window.Dispatcher.BeginInvoke(new Action(() => { if (!quitting) window.Hide(); }));
        };
        window.Closed += (s, e) => {
            timer.Stop();
            RemoveTrayIcon();
            SystemParameters.StaticPropertyChanged -= SystemAppearanceChanged;
            SystemEvents.UserPreferenceChanged -= UserPreferenceChanged;
            speech.Dispose();
        };
        ApplyTheme();
        ApplySize();
        Refresh(false);
        timer.Tick += (s, e) => Refresh(true);
        timer.Start();
        UpdateTrayIcon();
    }

    private void SystemAppearanceChanged(object sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == "HighContrast") window.Dispatcher.BeginInvoke(new Action(ApplyTheme));
    }

    private void UserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        window.Dispatcher.BeginInvoke(new Action(ApplyTheme));
    }

    private void ApplyTheme()
    {
        bool high = SystemParameters.HighContrast;
        bool dark = theme == "Dark" || (theme == "System" && Equals(Registry.GetValue(
            @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1), 0));
        Palette("CanvasBrush", dark ? "#17221E" : "#FAFBF8", high, SystemColors.WindowBrush);
        Palette("PanelBrush", dark ? "#172D24" : "#E6F2E6", high, SystemColors.WindowBrush);
        Palette("InkBrush", dark ? "#C1F4CF" : "#103D2B", high, SystemColors.WindowTextBrush);
        Palette("EdgeBrush", dark ? "#668779" : "#768C7C", high, SystemColors.WindowTextBrush);
        Palette("TrackBrush", dark ? "#40564B" : "#BDCFBF", high, SystemColors.GrayTextBrush);
        Palette("PrimaryBrush", dark ? "#C1F4CF" : "#184C36", high, SystemColors.HighlightBrush);
        Palette("PrimaryTextBrush", dark ? "#103D2B" : "#FFFFFF", high, SystemColors.HighlightTextBrush);
        Palette("FocusBrush", dark ? "#FFBE48" : "#9A4A00", high, SystemColors.HotTrackBrush);
    }

    private static void Palette(string name, string hex, bool high, Brush system)
    {
        Application.Current.Resources[name] = high ? system : new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
    }

    private void ApplySize() { level.FontSize = size * 96 / 72; }

    private void Refresh(bool automatic)
    {
        var next = Reading.Current();
        bool announce = automatic && next.ShouldAnnounce(reading, announcePower, announceLow ? (int?)lowThreshold : null);
        if (reading == null || next.Percent != reading.Percent || next.Status != reading.Status)
        {
            level.Text = next.Percent.HasValue ? next.Percent + "%" : "—";
            AutomationProperties.SetName(level, next.Percent.HasValue ? "Battery level, " + next.Percent + " percent" : "Battery level unavailable");
            status.Text = next.Status;
            for (int i = 0; i < gauge.Children.Count; i++)
                ((Border)gauge.Children[i]).SetResourceReference(Border.BackgroundProperty, i * 5 < next.Percent ? "InkBrush" : "TrackBrush");
        }
        reading = next;
        if (announce) speech.Say(next.Summary, voice);
    }

    private void Say(bool statusOnly)
    {
        Refresh(false);
        speech.Say(statusOnly ? reading.Status : reading.Summary, voice);
    }

    private void Shortcuts(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.F1)
        {
            MessageBox.Show(window, "Ctrl+S  Speak battery\nCtrl+C  Speak power status\nCtrl+,  Settings\nCtrl+L  Light appearance\nCtrl+D  Dark appearance\nCtrl+Q  Quit Battery % Viewer\nTab and Shift+Tab  Move between controls\nEscape  Close Settings", "Keyboard shortcuts");
            e.Handled = true; return;
        }
        if (Keyboard.Modifiers != ModifierKeys.Control) return;
        switch (e.Key)
        {
            case Key.S: Say(false); break;
            case Key.C: Say(true); break;
            case Key.OemComma: OpenSettings(); break;
            case Key.Q: Quit(); break;
            case Key.D: case Key.L:
                theme = e.Key == Key.D ? "Dark" : "Light"; Save("Theme", theme); ApplyTheme(); break;
            default: return;
        }
        e.Handled = true;
    }

    private static ComboBox Picker(Window dialog, string name, string[] choices, string selected, Action<string> change)
    {
        var box = (ComboBox)dialog.FindName(name);
        box.ItemsSource = choices;
        box.SelectedItem = choices.Contains(selected) ? selected : choices[0];
        box.SelectionChanged += (s, e) => change((string)box.SelectedItem);
        return box;
    }

    private static void Toggle(Window dialog, string name, bool initial, Action<bool> change)
    {
        var box = (CheckBox)dialog.FindName(name);
        box.IsChecked = initial;
        box.Checked += (s, e) => change(true);
        box.Unchecked += (s, e) => change(false);
    }

    private void OpenSettings()
    {
        var dialog = Load<Window>("Settings");
        dialog.Owner = window;
        var version = Assembly.GetExecutingAssembly().GetName().Version.ToString(2);
        ((TextBlock)dialog.FindName("Version")).Text = "Battery % Viewer, version " + version;
        dialog.MaxHeight = SystemParameters.WorkArea.Height;
        dialog.MaxWidth = SystemParameters.WorkArea.Width;
        var sizeSlider = (Slider)dialog.FindName("SizeSlider");
        var sizeValue = (TextBlock)dialog.FindName("SizeValue");
        sizeSlider.Minimum = MinPercentageSize;
        sizeSlider.Maximum = MaxPercentageSize;
        sizeSlider.Value = size;
        sizeValue.Text = size + " pt";
        sizeSlider.ValueChanged += (s, e) => {
            size = e.NewValue;
            sizeValue.Text = size + " pt";
            Save("PercentageFontSize", size.ToString());
            ApplySize();
        };
        Picker(dialog, "ThemePicker", Themes, theme, value => { theme = value; Save("Theme", theme); ApplyTheme(); });
        var voices = (ComboBox)dialog.FindName("Voices");
        voices.Items.Add(new ComboBoxItem { Content = "System default", Tag = "" });
        voices.SelectedIndex = 0;
        try
        {
            foreach (var v in Speech.Voices())
            {
                var item = new ComboBoxItem { Content = v.DisplayName + " · " + v.Language, Tag = v.Id };
                voices.Items.Add(item);
                if (v.Id == voice) voices.SelectedItem = item;
            }
        }
        catch (Exception) { voices.ToolTip = "Windows could not list installed voices."; }
        voices.SelectionChanged += (s, e) => { voice = (string)((ComboBoxItem)voices.SelectedItem).Tag; Save("Voice", voice); };
        ((Button)dialog.FindName("Preview")).Click += (s, e) => Say(false);
        Toggle(dialog, "Power", announcePower, value => { announcePower = value; Save("Power", value ? "1" : "0"); });
        Toggle(dialog, "Low", announceLow, value => { announceLow = value; Save("Low", value ? "1" : "0"); });
        var thresholdSlider = (Slider)dialog.FindName("LowThreshold");
        var thresholdValue = (TextBlock)dialog.FindName("LowThresholdValue");
        thresholdSlider.Minimum = MinLowThreshold;
        thresholdSlider.Maximum = MaxLowThreshold;
        thresholdSlider.Value = lowThreshold;
        thresholdValue.Text = lowThreshold + "%";
        thresholdSlider.ValueChanged += (s, e) => {
            lowThreshold = (int)Math.Round(e.NewValue);
            thresholdValue.Text = lowThreshold + "%";
            Save("LowBatteryThreshold", lowThreshold.ToString());
        };
        Toggle(dialog, "RunInBackground", runInBackground, value => {
            runInBackground = value;
            Save("RunInBackground", value ? "1" : "0");
            UpdateTrayIcon();
        });
        dialog.Loaded += (s, e) => sizeSlider.Focus();
        dialog.ShowDialog();
        ((Button)window.FindName("Settings")).Focus();
    }
}
