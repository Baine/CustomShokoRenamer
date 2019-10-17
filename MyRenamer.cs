using System.Text;
using Shoko.Commons.Extensions;
using Shoko.Models.Enums;
using Shoko.Models.Server;
using Shoko.Server.Models;
using Shoko.Server.Renamer;
using Shoko.Server;
using System.Linq;
using System.IO;
using NLog;
using Shoko.Server.Repositories;
using System.Collections.Generic;

namespace Renamer.Baine
{

    [Renamer("BaineRenamer", Description = "Baine's Custom Renamer")]
    public class MyRenamer : IRenamer
    {
        private static Logger logger = LogManager.GetCurrentClassLogger();
        public string GetFileName(SVR_VideoLocal_Place video) => GetFileName(video.VideoLocal);

        private string GetEpNameByPref(AniDB_Episode episode, string type, params string[] langs)
        {
            foreach (string lang in langs)
            {
                string title = RepoFactory.AniDB_Episode_Title.GetByEpisodeIDAndLanguage(episode.EpisodeID, lang).FirstOrDefault()?.Title;
                if (title != null) return title;
            }
            return RepoFactory.AniDB_Episode_Title.GetByEpisodeIDAndLanguage(episode.EpisodeID, "main")[0].Title;
        }

        public static string GetTitleByPref(SVR_AniDB_Anime anime, string type, params string[] langs)
        {
            var titles = anime.GetTitles();
            foreach (string lang in langs)
            {
                string title = titles.FirstOrDefault(s => s.Language == lang && s.TitleType == type)?.Title;
                if (title != null) return title;
            }

            return anime.MainTitle;
        }

        public string GetFileName(SVR_VideoLocal video)
        {
            if (!File.Exists(video.GetBestVideoLocalPlace().FullServerPath))
            {
                logger.Info("File no longer exists: " + video.GetBestVideoLocalPlace().FullServerPath);
                return "*Error: No such file exists in the FS.";
            }

            List<SVR_AnimeEpisode> episodes = null;
            AniDB_Episode episode = null;
            SVR_AniDB_Anime anime = null;
            try
            {
                episodes = video.GetAnimeEpisodes();
                episode = episodes[0].AniDB_Episode;
                anime = RepoFactory.AniDB_Anime.GetByAnimeID(episode.AnimeID);
            }
            catch
            {
                return "*Error: File is not linked to any episode.";
            }

            if (episode == null)
            {
                return "*Error: Unable to get episode for file";
            }

            if (anime == null)
            {
                return "*Error: Unable to get anime for file";
            }

            StringBuilder name = new StringBuilder();

            name.Append($"{GetTitleByPref(anime, "official", "de", "en", "x-jat")}");

            string prefix = "";

            if (episode.GetEpisodeTypeEnum() == EpisodeType.Credits) prefix = "C";
            if (episode.GetEpisodeTypeEnum() == EpisodeType.Other) prefix = "O";
            if (episode.GetEpisodeTypeEnum() == EpisodeType.Parody) prefix = "P";
            if (episode.GetEpisodeTypeEnum() == EpisodeType.Special) prefix = "S";
            if (episode.GetEpisodeTypeEnum() == EpisodeType.Trailer) prefix = "T";

            int epCount = 1;

            if (episode.GetEpisodeTypeEnum() == EpisodeType.Episode) epCount = anime.EpisodeCountNormal;
            if (episode.GetEpisodeTypeEnum() == EpisodeType.Special) epCount = anime.EpisodeCountSpecial;

            if (episodes.Count == 1)
                name.Append($" - {prefix}{PadNumberTo(episode.EpisodeNumber, epCount)}");
            else
            {
                int epNumbers = episodes.Count;
                name.Append($" - {prefix}{PadNumberTo(episode.EpisodeNumber, epCount)}-{prefix}{PadNumberTo(episodes[episodes.Count - 1].AniDB_Episode.EpisodeNumber, epCount)}");
            }

            string epTitle = GetEpNameByPref(episode, "official", "de", "en", "x-jat");

            if (episodes.Count > 1)
            {
                for (int i = 1; i < episodes.Count; i++)
                    epTitle += " & " + GetEpNameByPref(episodes[i].AniDB_Episode, "official", "de", "en", "x-jat");
            }

            if (epTitle.Length >100) epTitle = epTitle.Substring(0, 100 - 1) + "...";
            if (epTitle.EndsWith("...")) epTitle = string.Concat(epTitle, ".");
            name.Append($" - {epTitle}");

            string nameRet = Utils.ReplaceInvalidFolderNameCharacters(name.ToString());

            nameRet = string.Concat(nameRet, $"{Path.GetExtension(video.GetBestVideoLocalPlace().FilePath)}");

            if (string.IsNullOrEmpty(nameRet))
                return "*Error: The new filename is empty. Script error?";

            if (File.Exists(Path.Combine(Path.GetDirectoryName(video.GetBestVideoLocalPlace().FilePath), nameRet))) // Has potential null error, im bad pls fix ty 
                return "*Error: A file with this filename already exists";

            return nameRet;
        }

        string PadNumberTo(int number, int max, char padWith = '0')
        {
            return number.ToString().PadLeft(max.ToString().Length, padWith);
        }

        public (ImportFolder dest, string folder) GetDestinationFolder(SVR_VideoLocal_Place video)
        {
            SVR_AniDB_Anime anime = null;
            try
            {
                 anime = RepoFactory.AniDB_Anime.GetByAnimeID(video.VideoLocal.GetAnimeEpisodes()[0].AniDB_Episode.AnimeID);
            }
            catch
            {
                return (null, "*Error: File is not linked to any Episode");
            }
            if (anime == null)
                return (null, "*Error: File is not linked to any Episode");

            IEnumerable<string> subLanguagesFile = null;
            IEnumerable<string> audioLanguagesFile = null;
            try
            {
                subLanguagesFile = video.VideoLocal.Media.Parts.SelectMany(a => a.Streams).Where(a => a != null && a.StreamType == 3)
                    .Select(a => a.Language).Distinct();
                audioLanguagesFile = video.VideoLocal.Media.Parts.SelectMany(a => a.Streams).Where(a => a != null && a.StreamType == 2)
                    .Select(a => a.Language).Distinct();
            }
            catch
            {
            }

            List<Language> subLanguagesAniDB = new List<Language>();
            List<Language> audioLanguagesAniDB = new List<Language>();

            try
            {
                audioLanguagesAniDB = video.VideoLocal.GetAniDBFile().Languages;
                subLanguagesAniDB = video.VideoLocal.GetAniDBFile().Subtitles;
            }
            catch
            {
            }

            bool isMovie = anime.GetAnimeTypeEnum() == AnimeType.Movie;
            bool IsPorn = anime.Restricted > 0;
            bool isEngDub = false;
            bool isEngSub = false;
            bool isGerDub = false;
            bool isGerSub = false;

            if (subLanguagesAniDB != null && audioLanguagesAniDB != null &&
                subLanguagesAniDB.Count >=1 && audioLanguagesAniDB.Count >= 1)
            {
                if (audioLanguagesAniDB.Any(a => a.LanguageName.ToLower().Contains("german")))
                    isGerDub = true;
                if (subLanguagesAniDB.Any(a => a.LanguageName.ToLower().Contains("german")))
                    isGerSub = true;
                if (audioLanguagesAniDB.Any(a => a.LanguageName.ToLower().Contains("english")))
                    isEngDub = true;
                if (subLanguagesAniDB.Any(a => a.LanguageName.ToLower().Contains("english")))
                    isEngSub = true;
            }

            if (subLanguagesAniDB.Count == 0 || audioLanguagesAniDB.Count == 0)
            {
                if (audioLanguagesFile.Count() >= 1 && audioLanguagesFile.Any(a => a != null && a.ToLower().Contains("german")))
                    isGerDub = true;

                if (subLanguagesFile.Count() >= 1 && subLanguagesFile.Any(a => a != null && a.ToLower().Contains("german")))
                    isGerSub = true;

                if (audioLanguagesFile.Count() >= 1 && audioLanguagesFile.Any(a => a != null && a.ToLower().Contains("english")))
                    isEngDub = true;

                if (subLanguagesFile.Count() >= 1 && subLanguagesFile.Any(a => a != null && a.ToLower().Contains("english")))
                    isEngSub = true;
            }

            string location = Utils.IsLinux ? "/opt/share/" : "Z:\\";

            if (!IsPorn)
            {
                location += "Anime";
            }
            else
            {
                location += "Hentai";
            }

            location += Path.DirectorySeparatorChar;

            if (!isMovie)
                location += "Series";
            else
                location += "Movies";

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

                if (!isGerDub && !isGerSub && (isEngDub || isEngSub))
                {
                    location += "Other";
                    break;
                }

                location += "_manual";
                break;
                    
            }

            ImportFolder dest = RepoFactory.ImportFolder.GetByImportLocation(location);

            return (dest, Utils.ReplaceInvalidFolderNameCharacters(GetTitleByPref(anime, "official", "de", "en", "x-jat")));
        }
    }
}
