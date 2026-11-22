using System;
using System.Runtime.InteropServices;

internal sealed class Reading
{
    [StructLayout(LayoutKind.Sequential)]
    private struct PowerStatus
    {
        public byte ACLineStatus, BatteryFlag, BatteryLifePercent, SystemStatusFlag;
        public uint BatteryLifeTime, BatteryFullLifeTime;
    }

    [DllImport("kernel32.dll")]
    private static extern bool GetSystemPowerStatus(out PowerStatus status);

    public int? Percent;
    public bool? OnBattery;
    public string Status;
    public string Summary { get { return Percent.HasValue ? "Battery level " + Percent + " percent. " + Status + "." : Status; } }

    public static Reading Current()
    {
        PowerStatus p;
        return GetSystemPowerStatus(out p) ? Decode(p.ACLineStatus, p.BatteryFlag, p.BatteryLifePercent)
            : new Reading { Status = "Battery information unavailable" };
    }

    public static Reading Decode(byte ac, byte flags, byte level)
    {
        if (flags != 255 && (flags & 128) != 0) return new Reading { Status = "No battery detected" };
        var reading = new Reading {
            Percent = level <= 100 ? (int?)level : null,
            OnBattery = ac == 0 ? true : ac == 1 ? (bool?)false : null
        };
        if (ac == 0) reading.Status = "On battery power";
        else if (flags != 255 && (flags & 8) != 0) reading.Status = "Charging";
        else if (ac != 1) reading.Status = "Power source unknown";
        else reading.Status = level == 100 ? "Fully charged" : "Connected to power";
        if (!reading.Percent.HasValue) reading.Status = "Battery level unavailable. " + reading.Status;
        return reading;
    }

    public bool ShouldAnnounce(Reading old, bool power, int? lowThreshold)
    {
        if (old == null || !old.OnBattery.HasValue || !OnBattery.HasValue) return false;
        if (power && old.OnBattery != OnBattery) return true;
        return OnBattery.Value && Percent <= lowThreshold && (old.OnBattery == false || old.Percent > lowThreshold);
    }
}
