using System.Text;
using Shoko.Commons.Extensions;
using Shoko.Models.Enums;
using Shoko.Models.Server;
using Shoko.Server.Models;
using Shoko.Server.Renamer;
using Shoko.Server.Repositories;
using Shoko.Server;
using System.Linq;

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
                string title = RepoFactory.AniDB_Episode_Title.GetByEpisodeIDAndLanguage(episode.EpisodeID, lang)[0].Title;
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

            StringBuilder name = new StringBuilder();

            //if (!string.IsNullOrWhiteSpace(file.Anime_GroupNameShort))
            //    name.Append($"[{file.Anime_GroupNameShort}]");

            //name.Append($" {anime.PreferredTitle}");
            name.Append($"{GetTitleByPref(anime, "official", "de", "en", "x-jat")}");


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

            //name.Append($" ({video.VideoResolution}");
            //if (file.File_Source != null &&
            //    (file.File_Source.Equals("DVD", StringComparison.InvariantCultureIgnoreCase) ||
            //     file.File_Source.Equals("Blu-ray", StringComparison.InvariantCultureIgnoreCase)))

            //name.Append($" {file.File_Source}");

            //name.Append($" {(file?.File_VideoCodec ?? video.VideoCodec).Replace("\\", "").Replace("/", "")}".TrimEnd());

            //if (video.VideoBitDepth == "10")
            //    name.Append($" {video.VideoBitDepth}bit");
            //name.Append(')');

            //if (file.IsCensored != 0) name.Append(" [CEN]");

            //name.Append($" [{video.CRC32.ToUpper()}]");

            name.Append($" - {GetEpNameByPref(episode,"officle","de","en","x-jat")}");
            name.Append($"{System.IO.Path.GetExtension(video.GetBestVideoLocalPlace().FilePath)}");



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

            if (anime.TagsString.Contains("sex") || anime.TagsString.Contains("pornography") || anime.TagsString.Contains("18 restricted") || anime.Restricted > 0) location = "/porn/";

            ImportFolder dest = RepoFactory.ImportFolder.GetByImportLocation(location);

            return (dest, Utils.ReplaceInvalidFolderNameCharacters(GetTitleByPref(anime, "official", "de", "en", "x-jat")));
        }
    }
}
