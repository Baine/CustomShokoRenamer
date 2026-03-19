using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Extensions.Logging;
using Shoko.Abstractions.Enums;
using Shoko.Abstractions.Extensions;
using Shoko.Abstractions.Metadata.Shoko;
using Shoko.Abstractions.Plugin;
using Shoko.Abstractions.Relocation;
using Shoko.Abstractions.Utilities;
using Shoko.Abstractions.Video;
using Shoko.Abstractions.Video.Media;

namespace Shoko.Plugin.Renamer.Baine
{
    public class Plugin : IPlugin
    {
        public Guid ID => UuidUtility.GetV5(typeof(Plugin).FullName!);

        public string Name => nameof(Renamer);

        public string Description => "Baines Renamer";
    }

    public partial class Renamer(ILogger<Renamer> logger) : IRelocationProvider
    {
        public string Name => "BainesRenamer";

        public RelocationResult GetPath(RelocationContext ctx)
        {
            var result = new RelocationResult();

            string filename;
            try
            {
                filename = GetFilename(ctx);
            }
            catch (RenamerException e)
            {
                result.Error = new RelocationError(e.Message);
                return result;
            }

            result.FileName = filename;
            result.Path = GetTitleByPref(ctx.Series[0], true).ReplaceInvalidPathCharacters();
            result.ManagedFolder = GetManagedFolder(ctx);

            return result;
        }

        /// <summary>
        ///     Get the new path for a specified file.
        ///     The target path depends on age restriction and available dubs/subs
        /// </summary>
        /// <param name="ctx">Arguments for the process, contains FileInfo and more</param>
        public IManagedFolder GetManagedFolder(RelocationContext ctx)
        {
            //get the anime the file in question is linked to
            var anime = ctx.Series[0];

            logger.LogInformation($"Anime Name: {anime.PreferredTitle}");

            //check if the anime in question is restricted to 18+
            var isPorn = anime.Restricted;
            //get the FileInfo of the file in question
            var video = ctx.File;

            //instantiate lists for various stream information
            //these include Dub/Sub-Languages as readable by mediainfo
            //as well as Dub/Sub-Languages that AniDB provides for the file, if it is known
            IReadOnlyList<ITextStream> textStreamsFile = null;
            IReadOnlyList<IAudioStream> audioStreamsFile = null;
            IReadOnlyList<TitleLanguage> textLanguagesAniDb = null;
            IReadOnlyList<TitleLanguage> audioLanguagesAniDb = null;

            try
            {
                //sub streams as provided by mediainfo
                textStreamsFile = video.Video.MediaInfo.TextStreams;

                //dub streams as provided by mediainfo
                audioStreamsFile = video.Video.MediaInfo.AudioStreams;

                //sub languages as provided by anidb
                textLanguagesAniDb = video.Video.ReleaseInfo.MediaInfo.SubtitleLanguages;
                //sub languages as provided by anidb
                audioLanguagesAniDb = video.Video.ReleaseInfo.MediaInfo.AudioLanguages;
            }
            catch
            {
                // ignored
            }

            //define various bools
            //those will only get set to true if the respective stream in the relevant language is found
            var isEngDub = false;
            var isEngSub = false;
            var isGerDub = false;
            var isGerSub = false;

            //check if mediainfo provides us with audiostreams. if so, check if the language of them matches the desired one.
            //check if anidb provides us with information about the audiostreams. if so, check if the language of them matches the desired one.
            //if any of the above is true, set the respective bool to true
            //the same process applies to both dub and sub
            if ((audioStreamsFile != null && audioStreamsFile.Any(a => a.Language == TitleLanguage.German))
                || (audioLanguagesAniDb != null && audioLanguagesAniDb.Any(a => a == TitleLanguage.German)))
                isGerDub = true;

            if ((textStreamsFile != null && textStreamsFile.Any(t => t.Language == TitleLanguage.German))
                || (textLanguagesAniDb != null && textLanguagesAniDb.Any(t => t == TitleLanguage.German)))
                isGerSub = true;

            if ((audioStreamsFile != null && audioStreamsFile.Any(a => a.Language == TitleLanguage.English))
                || (audioLanguagesAniDb != null && audioLanguagesAniDb.Any(a => a == TitleLanguage.English)))
                isEngDub = true;

            if ((textStreamsFile != null && textStreamsFile.Any(t => t.Language == TitleLanguage.English))
                || (textLanguagesAniDb != null && textLanguagesAniDb.Any(t => t == TitleLanguage.English)))
                isEngSub = true;

            //define location based on the OS shokoserver is currently running on
            var location = RuntimeInformation.IsOSPlatform(OSPlatform.Linux) ? "/mnt/array/" : "Z:\\";

            //define the first subfolder depending on age restriction
            location += isPorn ? "Hentai" : "Anime";

            //add a directory separator char. this automatically switches between the proper char for the current OS
            location += Path.DirectorySeparatorChar;

            //a while true loop. be careful here, since this would always require a default break; otherwise this ever ends
            //used to evaluate the previously set bools and add the 2nd subfolder depending on available dubs/subs
            //if no choice can be made, a fallback folder is used for manual processing
            while (true)
            {
                if (isGerDub || video.Path.Contains(Path.DirectorySeparatorChar + "GerDub" + Path.DirectorySeparatorChar))
                {
                    location += "GerDub";
                    break;
                }

                if (isGerSub || video.Path.Contains(Path.DirectorySeparatorChar + "GerSub" + Path.DirectorySeparatorChar))
                {
                    location += "GerSub";
                    break;
                }

                if (isEngDub || isEngSub ||
                    video.Path.Contains(Path.DirectorySeparatorChar + "Other" + Path.DirectorySeparatorChar))
                {
                    location += "Other";
                    break;
                }

                location += "_manual";
                break;
            }

            return ctx.AvailableFolders.First(a => a.Path == location && a.DropFolderType.HasFlag(DropFolderType.Destination));
        }

        private static string GetTitleByPref(IShokoSeries anime, bool withAid) =>
            //no title found for the preferred languages, return the preferred title as defined by shoko
            withAid ? anime.PreferredTitle + " {anidb2-" + anime.AnidbAnimeID + "}" : anime.PreferredTitle.ToString();

        private static string GetEpNameByPref(IShokoEpisode episode) => episode.PreferredTitle.ToString();

        private string GetFilename(RelocationContext ctx)
        {
            //make args.FileInfo easier accessible. this refers to the actual file
            var video = ctx.File;

            //make the anime the episode belongs to easier accessible.
            var anime = ctx.Series.First();

            // Get the preferred title (Overriden, as shown in Desktop)
            var animeName = anime.PreferredTitle;

            logger.LogInformation($"Anime Name: {animeName}");

            //make the episode in question easier accessible. this refers to the episode the file is linked to
            var episodes = ctx.Episodes.ToList();

            //start an empty StringBuilder
            //will be used to store the new filename
            var name = new StringBuilder();

            //add the Anime title as defined by preference
            name.Append(GetTitleByPref(anime, false));
            //after this: name = Showname

            //only add prefixes and episode numbers when dealing with non-Movie files/episodes
            if (anime.Type != AnimeType.Movie)
            {
                //store the epsiode number as string. will be padded, determined by how many
                //episodes of the same type exist
                var paddedEpisodeNumber = new StringBuilder();

                foreach (var ep in episodes)
                    //perform action based on the episode type
                    //adding prefixes to the episode number for Credits, Specials, Trailers, Parodies ond episodes defined as Other
                    switch (ep.Type)
                    {
                        case EpisodeType.Episode:
                            paddedEpisodeNumber.Append('E');
                            paddedEpisodeNumber.Append(ep.EpisodeNumber.PadZeroes(anime.EpisodeCounts.Episodes));
                            break;
                        case EpisodeType.Credits:
                            paddedEpisodeNumber.Append('C');
                            paddedEpisodeNumber.Append(ep.EpisodeNumber.PadZeroes(anime.EpisodeCounts.Credits));
                            break;
                        case EpisodeType.Special:
                            paddedEpisodeNumber.Append('S');
                            paddedEpisodeNumber.Append(ep.EpisodeNumber.PadZeroes(anime.EpisodeCounts.Specials));
                            break;
                        case EpisodeType.Trailer:
                            paddedEpisodeNumber.Append('T');
                            paddedEpisodeNumber.Append(ep.EpisodeNumber.PadZeroes(anime.EpisodeCounts.Trailers));
                            break;
                        case EpisodeType.Parody:
                            paddedEpisodeNumber.Append('P');
                            paddedEpisodeNumber.Append(ep.EpisodeNumber.PadZeroes(anime.EpisodeCounts.Parodies));
                            break;
                        case EpisodeType.Other:
                            paddedEpisodeNumber.Append('O');
                            paddedEpisodeNumber.Append(ep.EpisodeNumber.PadZeroes(anime.EpisodeCounts.Others));
                            break;
                        default:
                            throw new ArgumentOutOfRangeException();
                    }

                //actually append the padded episode number, storing prefix as well
                name.Append($" - {paddedEpisodeNumber}");
                //after this: name = Showname - S03
            }

            name.Append(" - ");
            //get the preferred episode names and add them to the name
            foreach (var ep in episodes)
            {
                name.Append(GetEpNameByPref(ep));
                if (!ep.Equals(episodes.Last()))
                    name.Append("/");
            }

            if (name.Length > 225)
                name = new StringBuilder(name.ToString()[..225]);

            name = new StringBuilder(name.ToString().ReplaceInvalidPathCharacters());

            //if (name.ToString().EndsWith("\u2026"))
            //    name.Append(".");

            //after this: name = Showname - S03 - SpecialName

            //get and append the files extension
            if (name.ToString().EndsWith("\u2026"))
                name.Append("." + $"{Path.GetExtension(video.FileName)}");
            else
                name.Append($"{Path.GetExtension(video.FileName)}");
            //after this: name = Showname - S03 - Specialname.mkv

            //set the name as the result, replacing invalid path characters (e.g. '/') with similar looking Unicode Characters
            return name.ToString();
        }
    }
}