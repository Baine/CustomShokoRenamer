using System.Text;
using System.Linq;
using System.IO;
using System.Collections.Generic;
using Shoko.Server.Renamer;
using Shoko.Server.Models;
using Shoko.Models.Server;
using NLog;
using Shoko.Server.Repositories;
using Shoko.Commons.Extensions;
using Shoko.Models.Enums;
using Shoko.Server;
using Shoko.Models.MediaInfo;
using Shoko.Server.Utilities;

namespace Renamer.Baine
{

    [Renamer("BaineRenamer", Description = "Baine's Custom Renamer")]
    public class MyRenamer : IRenamer
    {
        private static Logger logger = LogManager.GetCurrentClassLogger();
        public string GetFileName(SVR_VideoLocal_Place video)
        {
            return GetFileName(video.VideoLocal);
        }

        private string GetEpNameByPref(AniDB_Episode episode, params string[] langs)
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
            List<AniDB_Anime_Title> titles = anime.GetTitles();
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

            List<SVR_AnimeEpisode> episodes;
            AniDB_Episode episode;
            SVR_AniDB_Anime anime;
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
                name.Append($" - {prefix}{PadNumberTo(episode.EpisodeNumber, epCount)}-{prefix}{PadNumberTo(episodes[episodes.Count - 1].AniDB_Episode.EpisodeNumber, epCount)}");
            }

            string epTitle = GetEpNameByPref(episode, "de", "en", "x-jat");

            if (episodes.Count > 1)
            {
                for (int i = 1; i < episodes.Count; i++)
                    epTitle += " & " + GetEpNameByPref(episodes[i].AniDB_Episode, "de", "en", "x-jat");
            }

            if (epTitle.Length >100) epTitle = epTitle.Substring(0, 100 - 1) + "...";
            if (epTitle.EndsWith("...")) epTitle = string.Concat(epTitle, ".");
            name.Append($" - {epTitle}");

            string nameRet = Utils.ReplaceInvalidFolderNameCharacters(name.ToString());

            nameRet = string.Concat(nameRet, $"{Path.GetExtension(video.GetBestVideoLocalPlace().FilePath)}");

            if (string.IsNullOrEmpty(nameRet))
                return "*Error: The new filename is empty. Script error?";

            if (File.Exists(Path.Combine(Path.GetDirectoryName(video.GetBestVideoLocalPlace().FilePath)!, nameRet))) // Has potential null error, im bad pls fix ty 
                return "*Error: A file with this filename already exists";

            return nameRet;
        }

        string PadNumberTo(int number, int max, char padWith = '0')
        {
            return number.ToString().PadLeft(max.ToString().Length, padWith);
        }

        public (ImportFolder dest, string folder) GetDestinationFolder(SVR_VideoLocal_Place video)
        {
            SVR_AniDB_Anime anime;
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
            
            List<TextStream>  textStreamsFile = null;
            List<AudioStream> audioStreamsFile = null;

            try
            {
                textStreamsFile = video.VideoLocal.Media.TextStreams;
                audioStreamsFile = video.VideoLocal.Media.AudioStreams;
            }
            catch
            {
                // ignored
            }

            List<Language> subLanguagesAniDb = new List<Language>();
            List<Language> audioLanguagesAniDb = new List<Language>();

            try
            {
                audioLanguagesAniDb = video.VideoLocal.GetAniDBFile().Languages;
                subLanguagesAniDb = video.VideoLocal.GetAniDBFile().Subtitles;
            }
            catch
            {
                // ignored
            }

            bool isPorn = anime.Restricted > 0;
            bool isEngDub = false;
            bool isEngSub = false;
            bool isGerDub = false;
            bool isGerSub = false;

            if (subLanguagesAniDb?.Count >=1 && audioLanguagesAniDb?.Count >= 1)
            {
                if (audioLanguagesAniDb.Any(a => a.LanguageName.ToLower().Contains("german")))
                    isGerDub = true;
                if (subLanguagesAniDb.Any(a => a.LanguageName.ToLower().Contains("german")))
                    isGerSub = true;
                if (audioLanguagesAniDb.Any(a => a.LanguageName.ToLower().Contains("english")))
                    isEngDub = true;
                if (subLanguagesAniDb.Any(a => a.LanguageName.ToLower().Contains("english")))
                    isEngSub = true;
            }

            if (audioLanguagesAniDb != null && (subLanguagesAniDb != null && ((subLanguagesAniDb.Count == 0 || audioLanguagesAniDb.Count == 0) && ((audioStreamsFile?.Count() >= 1) || (textStreamsFile?.Count() >= 1)))))
            {
                if(audioStreamsFile!.Any(a => a.LanguageCode?.ToLower() == "deu" ))
                    isGerDub = true;

                if(textStreamsFile.Any(a => a.LanguageCode?.ToLower() == "deu" ))
                    isGerSub = true;

                if(audioStreamsFile.Any(a => a.LanguageCode?.ToLower() == "ger" ))
                    isGerDub = true;

                if(textStreamsFile.Any(a => a.LanguageCode?.ToLower() == "ger" ))
                    isGerSub = true;

                if(audioStreamsFile.Any(a => a.LanguageCode?.ToLower() == "eng" ))
                    isEngDub = true;

                if(textStreamsFile.Any(a => a.LanguageCode?.ToLower() == "eng" ))
                    isEngSub = true;
            }

            string location = Utils.IsLinux ? "/anime/" : "Z:\\";

            if (!isPorn)
            {
                location += "Anime";
            }
            else
            {
                location += "Hentai";
            }

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

            ImportFolder dest = RepoFactory.ImportFolder.GetByImportLocation(location);

            return (dest, Utils.ReplaceInvalidFolderNameCharacters(GetTitleByPref(anime, "official", "de", "en", "x-jat")));
        }
    }
}
