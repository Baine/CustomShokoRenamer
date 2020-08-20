using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using NLog;
using Shoko.Plugin.Abstractions;
using Shoko.Plugin.Abstractions.DataModels;

namespace Renamer.Baine
{
    public class MyRenamer : IRenamer
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

        public static string GetTitleByPref(IAnime anime, TitleType type, params TitleLanguage[] langs)
        {
            var titles = (List<AnimeTitle>)anime.Titles;
            foreach (TitleLanguage lang in langs)
            {
                string title = titles.FirstOrDefault(s => s.Language == lang && s.Type == type)?.Title;
                if (title != null) return title;
            }

            return anime.PreferredTitle;
        }

        private string GetEpNameByPref(IEpisode episode, params TitleLanguage[] langs)
        {
            foreach (TitleLanguage lang in langs)
            {
                string title = episode.Titles.FirstOrDefault(s => s.Language == lang).Title;
                if (title != null) return title;
            }
            return episode.Titles.FirstOrDefault().Title;
        }

        public void GetFilename(RenameEventArgs args)
        {
            var video = args.FileInfo;
            var episode = args.EpisodeInfo.First();
            var anime = args.AnimeInfo.First();

            StringBuilder name = new StringBuilder();

            if (!string.IsNullOrWhiteSpace(video.AniDBFileInfo.ReleaseGroup.ShortName))
                name.Append($"[{video.AniDBFileInfo.ReleaseGroup.ShortName}]");

            name.Append($"{GetTitleByPref(anime, TitleType.Official, TitleLanguage.German, TitleLanguage.English, TitleLanguage.Romaji)}");

            if (anime.Type != AnimeType.Movie)
            {
                string paddedEpisodeNumber = null;
                switch (episode.Type)
                {
                    case EpisodeType.Episode:
                        paddedEpisodeNumber = episode.Number.PadZeroes(anime.EpisodeCounts.Episodes);
                        break;
                    case EpisodeType.Credits:
                        paddedEpisodeNumber = "C" + episode.Number.PadZeroes(anime.EpisodeCounts.Credits);
                        break;
                    case EpisodeType.Special:
                        paddedEpisodeNumber = "S" + episode.Number.PadZeroes(anime.EpisodeCounts.Specials);
                        break;
                    case EpisodeType.Trailer:
                        paddedEpisodeNumber = "T" + episode.Number.PadZeroes(anime.EpisodeCounts.Trailers);
                        break;
                    case EpisodeType.Parody:
                        paddedEpisodeNumber = "P" + episode.Number.PadZeroes(anime.EpisodeCounts.Parodies);
                        break;
                    case EpisodeType.Other:
                        paddedEpisodeNumber = "O" + episode.Number.PadZeroes(anime.EpisodeCounts.Others);
                        break;
                }

                name.Append($" - {paddedEpisodeNumber}");
            }

            name.Append($" - {GetEpNameByPref(episode, TitleLanguage.German, TitleLanguage.English, TitleLanguage.Romaji)}");
            name.Append($"{Path.GetExtension(video.Filename)}");

            args.Result = name.ToString().ReplaceInvalidPathCharacters();
        }

        public void GetDestination(MoveEventArgs args)
        {
            var anime = args.AnimeInfo.First();
            bool isPorn = anime.Restricted;

            IList<ITextStream> textStreamsFile = null;
            IList<IAudioStream> audioStreamsFile = null;

            try
            {
                textStreamsFile = args.FileInfo.MediaInfo.Subs;
                audioStreamsFile = args.FileInfo.MediaInfo.Audio;
            }
            catch
            {
                // ignored
            }

            bool isEngDub = false;
            bool isEngSub = false;
            bool isGerDub = false;
            bool isGerSub = false;

            if (audioStreamsFile!.Any(a => a.LanguageCode?.ToLower() == "de"))
                isGerDub = true;

            if (textStreamsFile.Any(a => a.LanguageCode?.ToLower() == "de"))
                isGerSub = true;

            if (audioStreamsFile.Any(a => a.LanguageCode?.ToLower() == "en"))
                isEngDub = true;

            if (textStreamsFile.Any(a => a.LanguageCode?.ToLower() == "en"))
                isEngSub = true;

            ////var subLanguagesAniDB;
            ////var audioLanguagesAniDB;

            //try
            //{
            //    //var subLanguagesAniDB = args.FileInfo.AniDBFileInfo.
            //}
            //catch
            //{
            //    // ignored
            //}


            var location = RuntimeInformation.IsOSPlatform(OSPlatform.Linux) ? "/mnt/array/" : "Z:\\";
            location += isPorn ? "Hentai" : "Anime";
            
            location += Path.DirectorySeparatorChar;

            while (true)
            {
                if (isGerDub)
                {
                    location += "GerDub";
                    break;
                }

                if (isGerSub)
                {
                    location += "GerSub";
                    break;
                }

                if ((isEngDub || isEngSub))
                {
                    location += "Other";
                    break;
                }

                location += "_manual";
                break;

            }


            var dest = args.AvailableFolders.FirstOrDefault(a => a.Location == location);

            args.DestinationImportFolder = dest;
            Logger.Info($"DestinationImportFolder: {args.DestinationImportFolder}");
            args.DestinationPath = GetTitleByPref(anime, TitleType.Official, TitleLanguage.German, TitleLanguage.English, TitleLanguage.Romaji).ReplaceInvalidPathCharacters();
            Logger.Info($"DestinationPath: {args.DestinationPath}");
        }

        public void Load()
        {
        }

        public void OnSettingsLoaded(IPluginSettings settings)
        {
        }

        public string Name => "BaineRenamer";
    }
}
                                                                                                      