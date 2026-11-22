using System;
using System.Collections.Generic;
using System.Linq;
using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.Media.SpeechSynthesis;

internal sealed class Speech : IDisposable
{
    private MediaPlayer player;
    private SpeechSynthesisStream audio;
    private MediaSource source;
    private int request;
    public event Action<string> Failed;

    public static IEnumerable<VoiceInformation> Voices()
    {
        return SpeechSynthesizer.AllVoices.OrderBy(v => v.DisplayName).ToArray();
    }

    public async void Say(string text, string voiceId)
    {
        int current = ++request;
        try
        {
            StopPlayback();
            using (var synth = new SpeechSynthesizer())
            {
                if (!String.IsNullOrEmpty(voiceId))
                    synth.Voice = Voices().FirstOrDefault(v => v.Id == voiceId) ?? SpeechSynthesizer.DefaultVoice;
                var stream = await synth.SynthesizeTextToStreamAsync(text);
                if (request != current) { stream.Dispose(); return; }
                audio = stream;
                source = MediaSource.CreateFromStream(audio, audio.ContentType);
                player = new MediaPlayer { CommandManager = { IsEnabled = false } };
                player.MediaFailed += (s, e) => { if (current == request) Report("Windows could not play the speech audio."); };
                player.Source = source;
                player.Play();
            }
        }
        catch (Exception ex) { if (current == request) Report("Windows could not speak this reading. " + ex.Message); }
    }

    private void Report(string message) { if (Failed != null) Failed(message); }

    private void StopPlayback()
    {
        if (player != null) { player.Dispose(); player = null; }
        if (source != null) { source.Dispose(); source = null; }
        if (audio != null) { audio.Dispose(); audio = null; }
    }

    public void Dispose() { ++request; StopPlayback(); }
}
