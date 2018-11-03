﻿using System;
using System.Collections.Generic;
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
                name.Append($" - {prefix}{PadNumberTo(episode.EpisodeNumber, epCount)}-{prefix}{PadNumberTo(episodes[episodes.Count-1].AniDB_Episode.EpisodeNumber, epCount)}");
            }

            string epTitle = GetEpNameByPref(episode, "official", "de", "en", "x-jat");
            if (episodes.Count > 1)
            {
                for(int i=1;i<episodes.Count;i++)
                    epTitle += " & " + GetEpNameByPref(episodes[i].AniDB_Episode, "official", "de", "en", "x-jat");
            }
            if (epTitle.Length > 75) epTitle = epTitle.Substring(0, 75 - 1) + "...";
            name.Append($" - {epTitle}");
            

            name.Append($"{Path.GetExtension(video.GetBestVideoLocalPlace().FilePath)}");

            if (string.IsNullOrEmpty(name.ToString()))
                return "*Error: The new filename is empty. Script error?";

            return File.Exists(Path.Combine(Path.GetDirectoryName(video.GetBestVideoLocalPlace().FilePath), Utils.ReplaceInvalidFolderNameCharacters(name.ToString())))
                ? "*Error: A file with this filename already exists"
                : Utils.ReplaceInvalidFolderNameCharacters(name.ToString());
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
                return (null, "*Error: File not linked to any Episode");
            }

            var location = "/opt/share/Anime/Series/";
            bool isPorn = anime.Restricted > 0;
            if (isPorn) location = "/opt/share/Hentai/Series";

            if (anime.GetAnimeTypeEnum() == AnimeType.Movie) location = "/opt/share/Anime/Movies/";
            if (anime.GetAnimeTypeEnum() == AnimeType.Movie && isPorn) location = "/opt/share/Hentai/Movies/";

            if (!Utils.IsLinux)
            {
                location = "W:\\Anime\\Series";
                if (isPorn) location = "W:\\Hentai\\Series";
                if (anime.GetAnimeTypeEnum() == AnimeType.Movie) location = "W:\\Anime\\Movies";
                if (anime.GetAnimeTypeEnum() == AnimeType.Movie && isPorn) location = "W:\\Hentai\\Movies";
            }

            ImportFolder dest = RepoFactory.ImportFolder.GetByImportLocation(location);

            return (dest, Utils.ReplaceInvalidFolderNameCharacters(GetTitleByPref(anime, "official", "de", "en", "x-jat")));
        }
    }
}
