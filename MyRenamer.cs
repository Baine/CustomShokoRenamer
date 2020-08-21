using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using Shoko.Plugin.Abstractions;
using Shoko.Plugin.Abstractions.DataModels;

namespace Renamer.Baine
{
    public class MyRenamer : IRenamer
    {
        private string GetTitleByPref(IAnime anime, TitleType type, params TitleLanguage[] langs)
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
                string title = episode.Titles.FirstOrDefault(s => s.Language == lang)?.Title;
                if (title != null) return title;
            }
            return episode.Titles.First().Title;
        }

        public void GetFilename(RenameEventArgs args)
        {
            var video = args.FileInfo;
            var episode = args.EpisodeInfo.First();
            var anime = args.AnimeInfo.First();

            StringBuilder name = new StringBuilder();

            name.Append(GetTitleByPref(anime, TitleType.Official, TitleLanguage.German, TitleLanguage.English, TitleLanguage.Romaji));

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

            IReadOnlyList<ITextStream> textStreamsFile = null;
            IReadOnlyList<IAudioStream> audioStreamsFile = null;
            IReadOnlyList<TitleLanguage> textLanguagesAniDB = null;
            IReadOnlyList<TitleLanguage> audioLanguagesAniDB = null;

            try
            {
                textStreamsFile = args.FileInfo.MediaInfo.Subs;
                audioStreamsFile = args.FileInfo.MediaInfo.Audio;
                textLanguagesAniDB = args.FileInfo.AniDBFileInfo.MediaInfo.SubLanguages;
                audioLanguagesAniDB = args.FileInfo.AniDBFileInfo.MediaInfo.AudioLanguages;
            }
            catch
            {
                // ignored
            }

            bool isEngDub = false;
            bool isEngSub = false;
            bool isGerDub = false;
            bool isGerSub = false;

            if ((audioStreamsFile != null && audioStreamsFile!.Any(a => a!.LanguageCode?.ToLower() == "ger")) || (audioLanguagesAniDB != null && audioLanguagesAniDB!.Any(a => a == TitleLanguage.German)))
                isGerDub = true;

            if ((textStreamsFile != null && textStreamsFile!.Any(t => t!.LanguageCode?.ToLower() == "ger")) || (textLanguagesAniDB != null && textLanguagesAniDB!.Any(t => t == TitleLanguage.German)))
                isGerSub = true;

            if ((audioStreamsFile != null && audioStreamsFile!.Any(a => a!.LanguageCode?.ToLower() == "eng")) || (audioLanguagesAniDB != null && audioLanguagesAniDB!.Any(a => a == TitleLanguage.English)))
                isGerDub = true;

            if ((textStreamsFile != null && textStreamsFile!.Any(t => t!.LanguageCode?.ToLower() == "eng")) || (textLanguagesAniDB != null && textLanguagesAniDB!.Any(t => t == TitleLanguage.English)))
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
            args.DestinationPath = GetTitleByPref(anime, TitleType.Official, TitleLanguage.German, TitleLanguage.English, TitleLanguage.Romaji).ReplaceInvalidPathCharacters();
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
                                                                                                      