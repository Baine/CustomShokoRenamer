using System.Text;
using Shoko.Commons.Extensions;
using Shoko.Models.Enums;
using Shoko.Models.Server;
using Shoko.Server.Models;
using Shoko.Server.Renamer;
using Shoko.Server.Repositories;
using Shoko.Server;
using System.Linq;
using System.IO;

namespace Renamer.Baine
{

    [Renamer("BaineRenamer", Description = "Baine's Custom Renamer")]
    public class MyRenamer : IRenamer
    {
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
            var file = video.GetAniDBFile();
            var episode = video.GetAnimeEpisodes()[0].AniDB_Episode;
            var anime = RepoFactory.AniDB_Anime.GetByAnimeID(episode.AnimeID);

            if(file == null)
            {
                return "*Error: Unable to access file";
            }

            if(episode == null)
            {
                return "*Error: Unable to get episode for file";
            }

            if (anime == null)
            {
                return "*Error: Unable to get anime for file";
            }

            StringBuilder name = new StringBuilder();

            string prefix = "";

            if (anime.AnimeType != (int)AnimeType.Movie)
            {
                if (episode.GetEpisodeTypeEnum() == EpisodeType.Credits) prefix = "C";
                if (episode.GetEpisodeTypeEnum() == EpisodeType.Other) prefix = "O";
                if (episode.GetEpisodeTypeEnum() == EpisodeType.Parody) prefix = "P";
                if (episode.GetEpisodeTypeEnum() == EpisodeType.Special) prefix = "S";
                if (episode.GetEpisodeTypeEnum() == EpisodeType.Trailer) prefix = "T";
            }

            int epCount = 1;

            if (episode.GetEpisodeTypeEnum() == EpisodeType.Episode) epCount = anime.EpisodeCountNormal;
            if (episode.GetEpisodeTypeEnum() == EpisodeType.Special) epCount = anime.EpisodeCountSpecial;

            name.Append($" - {prefix}{PadNumberTo(episode.EpisodeNumber, epCount)}");

            var epTitle = GetTitleByPref(anime, "official", "de", "en", "x-jat");
            if (epTitle.Length > 33) epTitle = epTitle.Substring(0, 33 - 1) + "...";
            name.Append($" - {epTitle}");

            name.Append($"{Path.GetExtension(video.GetBestVideoLocalPlace().FilePath)}");

            if (string.IsNullOrEmpty(name.ToString()))
                return "*Error: The new filename is empty. Script error?";

            if (File.Exists(Path.Combine(Path.GetDirectoryName(video.GetBestVideoLocalPlace().FilePath), name.ToString()))) // Has potential null error, im bad pls fix ty 
                return "*Error: A file with this filename already exists";

            return Utils.ReplaceInvalidFolderNameCharacters(name.ToString());
        }

        string PadNumberTo(int number, int max, char padWith = '0')
        {
            return number.ToString().PadLeft(max.ToString().Length, padWith);
        }

        public (ImportFolder dest, string folder) GetDestinationFolder(SVR_VideoLocal_Place video)
        {
            var anime = RepoFactory.AniDB_Anime.GetByAnimeID(video.VideoLocal.GetAnimeEpisodes()[0].AniDB_Episode.AnimeID);
            var location = "/anime/";
            bool IsPorn = anime.Restricted > 0;
            if (IsPorn) location = "/hentai/";

            ImportFolder dest = RepoFactory.ImportFolder.GetByImportLocation(location);

            return (dest, Utils.ReplaceInvalidFolderNameCharacters(GetTitleByPref(anime, "official", "de", "en", "x-jat")));
        }
    }
}
