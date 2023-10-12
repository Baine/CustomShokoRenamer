using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using NLog;
using Shoko.Plugin.Abstractions;
using Shoko.Plugin.Abstractions.Attributes;
using Shoko.Plugin.Abstractions.DataModels;

namespace Renamer.Baine
{
    /// <summary>
    /// Baines custom Renamer
    /// Target Folder Structure is based on available dub/sub languages, as well being restricted to being >18+
    /// </summary>
    [Renamer("BaineRenamer", Description = "Baines Renamer")]
    public class MyRenamer : IRenamer
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
        /// <summary>
        /// Get anime title as specified by preference. Order matters. if nothing found, preferred title is returned
        /// </summary>
        /// <param name="anime">IAnime object representing the Anime the title has to be searched for</param>
        /// <param name="type">TitleType, eg. TitleType.Official or TitleType.Short </param>
        /// <param name="langs">Arguments Array taking in the TitleLanguages that should be search for.</param>
        /// <returns>string representing the Anime Title for the first language a title is found for</returns>
        private string GetTitleByPref(IAnime anime, TitleType type, params TitleLanguage[] langs)
        {
            //get all titles
            var titles = (List<AnimeTitle>)anime.Titles;

            //iterate over the given TitleLanguages in langs
            foreach (TitleLanguage lang in langs)
            {
                //set title to the first found title of the defined language. if nothing found title will stay null
                string title = titles.FirstOrDefault(s => s.Language == lang && s.Type == type)?.Title;

                //if title is found, aka title not null, return it
                if (title != null) return title;
            }

            //no title found for the preferred languages, return the preferred title as defined by shoko
            return anime.PreferredTitle;
        }
        public static string ownReplaceInvalidPathCharacters(this string path)
        {
            string text = path.Replace("*", "★");
            text = text.Replace("|", "¦");
            text = text.Replace("\\", "⧹");
            text = text.Replace("/", "⁄");
            text = text.Replace(":", "։");
            text = text.Replace("\"", "″");
            text = text.Replace(">", "›");
            text = text.Replace("<", "‹");
            text = text.Replace("?", "？");
            text = text.Replace("...", "…");
            if (text.StartsWith(".", StringComparison.Ordinal))
            {
                text = "․" + text.Substring(1, text.Length - 1);
            }

            //if (text.EndsWith(".", StringComparison.Ordinal))
            //{
            //    text = text.Substring(0, text.Length - 1) + "․";
            //}

            return text.Trim();
        }

        public static string PadZeroes(this int num, int total)
        {
            int length = total.ToString().Length;
            return num.ToString().PadLeft(length, '0');
        }

        /// <summary>
        /// Get Episode Name/Title as specified by preference. if nothing found, the first available is returned
        /// </summary>
        /// <param name="episode">IEpisode object representing the episode to search the name for</param>
        /// <param name="langs">Arguments array taking in the TitleLanguages that should be search for.</param>
        /// <returns>string representing the episode name for the first language a name is found for</returns>
        private string GetEpNameByPref(IEpisode episode, params TitleLanguage[] langs)
        {
            //iterate over all passed TitleLanguages
            foreach (TitleLanguage lang in langs)
            {
                //set the title to the first found title whose language matches with the search one.
                //if none is found, title is null
                string title = episode.Titles.FirstOrDefault(s => s.Language == lang)?.Title;

                //return the found title if title is not null
                if (title != null) return title.Substring(0,Math.Min(title.Length, 150));
            }

            //no title for any given TitleLanguage found, return the first available.
            return episode.Titles.First().Title.Substring(0, Math.Min(episode.Titles.First().Title.Length, 150));
        }

        /// <summary>
        /// Get the new filename for a specified file
        /// </summary>
        /// <param name="args">Renaming Arguments, e.g. available folders</param>
        public string GetFilename(RenameEventArgs args)
        {

            //make args.FileInfo easier accessible. this refers to the actual file
            var video = args.FileInfo;

            // Get the Anime Info
            IAnime animeInfo = args.AnimeInfo.FirstOrDefault();

            // Get the preferred title (Overriden, as shown in Desktop)
            string animeName = animeInfo?.PreferredTitle;

            //make the anime the episode belongs to easier accessible.
            IAnime anime = args.AnimeInfo?.FirstOrDefault();
            if (anime == null)
            {
                // throw new Exception("Error in renamer: Anime name not found!");
                args.Cancel = true;
                return null;
            }
            Logger.Info($"Anime Name: {animeName}");

            //make the episode in question easier accessible. this refers to the episode the file is linked to
            var episodes = args.EpisodeInfo.ToList();

            //start an empty StringBuilder
            //will be used to store the new filename
            StringBuilder name = new StringBuilder();

            //add the Anime title as defined by preference
            name.Append(GetTitleByPref(anime, TitleType.Official, TitleLanguage.German, TitleLanguage.English, TitleLanguage.Romaji));
            //after this: name = Showname

            //only add prefixes and episode numbers when dealing with non-Movie files/episodes
            if (anime.Type != AnimeType.Movie)
            {
                //store the epsiode number as string. will be padded, determined by how many
                //episodes of the same type exist
                StringBuilder paddedEpisodeNumber = new StringBuilder();

                foreach (var ep in episodes)
                {
                    //perform action based on the episode type
                    //adding prefixes to the episode number for Credits, Specials, Trailers, Parodies ond episodes defined as Other
                    switch (ep.Type)
                    {
                        case EpisodeType.Episode:
                            paddedEpisodeNumber.Append("E");
                            paddedEpisodeNumber.Append(ep.Number.PadZeroes(anime.EpisodeCounts.Episodes));
                            break;
                        case EpisodeType.Credits:
                            paddedEpisodeNumber.Append("C");
                            paddedEpisodeNumber.Append(ep.Number.PadZeroes(anime.EpisodeCounts.Credits));
                            break;
                        case EpisodeType.Special:
                            paddedEpisodeNumber.Append("S");
                            paddedEpisodeNumber.Append(ep.Number.PadZeroes(anime.EpisodeCounts.Specials));
                            break;
                        case EpisodeType.Trailer:
                            paddedEpisodeNumber.Append("T");
                            paddedEpisodeNumber.Append(ep.Number.PadZeroes(anime.EpisodeCounts.Trailers));
                            break;
                        case EpisodeType.Parody:
                            paddedEpisodeNumber.Append("P");
                            paddedEpisodeNumber.Append(ep.Number.PadZeroes(anime.EpisodeCounts.Parodies));
                            break;
                        case EpisodeType.Other:
                            paddedEpisodeNumber.Append("O");
                            paddedEpisodeNumber.Append(ep.Number.PadZeroes(anime.EpisodeCounts.Others));
                            break;
                    }
                }
                //actually append the padded episode number, storing prefix as well
                name.Append($" - {paddedEpisodeNumber}");
                //after this: name = Showname - S03
            }

            name.Append(" - ");
            //get the preferred episode names and add them to the name
            foreach (var ep in episodes)
            {
                name.Append(GetEpNameByPref(ep, TitleLanguage.German, TitleLanguage.English, TitleLanguage.Romaji));
                if (!ep.Equals(episodes.Last()))
                    name.Append("/");
            }
            
            if(name.ToString().Length > 150)
                name = new StringBuilder(name.ToString().ownReplaceInvalidPathCharacters().Substring(0, 150));
            

            //if (name.ToString().EndsWith("\u2026"))
            //    name.Replace("\u2026", "...");

            //after this: name = Showname - S03 - SpecialName

            //get and append the files extension
            name.Append($"{Path.GetExtension(video.Filename)}");
            //after this: name = Showname - S03 - Specialname.mkv

            //set the name as the result, replacing invalid path characters (e.g. '/') with similar looking Unicode Characters
            return name.ToString();
        }

        /// <summary>
        /// Get the new path for a specified file.
        /// The target path depends on age restriction and available dubs/subs
        /// </summary>
        /// <param name="args">Arguments for the process, contains FileInfo and more</param>
        public (IImportFolder destination, string subfolder) GetDestination(MoveEventArgs args)
        {
            //get the anime the file in question is linked to
            IAnime anime = args.AnimeInfo?.FirstOrDefault();
            if (anime == null)
            {
                //throw new Exception("Error in renamer: Anime name not found!");
                args.Cancel = true;
                return (null, null);
            }
            Logger.Info($"Anime Name: {anime?.PreferredTitle}");


            //get the FileInfo of the file in question
            var video = args.FileInfo;

            //check if the anime in question is restricted to 18+
            bool isPorn = anime.Restricted;

            //instantiate lists for various stream information
            //these include Dub/Sub-Languages as readable by mediainfo
            //as well as Dub/Sub-Languages that AniDB provides for the file, if it is known
            IReadOnlyList<ITextStream> textStreamsFile = null;
            IReadOnlyList<IAudioStream> audioStreamsFile = null;
            IReadOnlyList<TitleLanguage> textLanguagesAniDB = null;
            IReadOnlyList<TitleLanguage> audioLanguagesAniDB = null;

            try
            {
                //sub streams as provided by mediainfo
                textStreamsFile = video.MediaInfo.Subs;

                //dub streams as provided by mediainfo
                audioStreamsFile = video.MediaInfo.Audio;

                //sub languages as provided by anidb
                textLanguagesAniDB = video.AniDBFileInfo.MediaInfo.SubLanguages;

                //sub languages as provided by anidb
                audioLanguagesAniDB = video.AniDBFileInfo.MediaInfo.AudioLanguages;
            }
            catch
            {
                // ignored
            }

            //define various bools
            //those will only get set to true if the respective stream in the relevant language is found
            bool isEngDub = false;
            bool isEngSub = false;
            bool isGerDub = false;
            bool isGerSub = false;

            //check if mediainfo provides us with audiostreams. if so, check if the language of any of them matches the desired one.
            //check if anidb provides us with information about the audiostreams. if so, check if the language of any of them matches the desired one.
            //if any of the above is true, set the respective bool to true
            //the same process applies to both dub and sub
            if ((audioStreamsFile != null && audioStreamsFile!.Any(a => a!.LanguageCode?.ToLower() == "ger")) || (audioLanguagesAniDB != null && audioLanguagesAniDB!.Any(a => a == TitleLanguage.German)))
                isGerDub = true;

            if ((textStreamsFile != null && textStreamsFile!.Any(t => t!.LanguageCode?.ToLower() == "ger")) || (textLanguagesAniDB != null && textLanguagesAniDB!.Any(t => t == TitleLanguage.German)))
                isGerSub = true;

            if ((audioStreamsFile != null && audioStreamsFile!.Any(a => a!.LanguageCode?.ToLower() == "eng")) || (audioLanguagesAniDB != null && audioLanguagesAniDB!.Any(a => a == TitleLanguage.English)))
                isEngDub = true;

            if ((textStreamsFile != null && textStreamsFile!.Any(t => t!.LanguageCode?.ToLower() == "eng")) || (textLanguagesAniDB != null && textLanguagesAniDB!.Any(t => t == TitleLanguage.English)))
                isEngSub = true;

            //define location based on the OS shokoserver is currently running on
            var location = RuntimeInformation.IsOSPlatform(OSPlatform.Linux) ? "/mnt/array/" : "Z:\\";

            //define the first subfolder depending on age restriction
            location += isPorn ? "Hentai" : "Anime";
            
            //add a directory separator char. this automatically switches between the proper char for the current OS
            location += Path.DirectorySeparatorChar;

            //a while true loop. be carefull here, since this would always require a default break; otherwise this ever ends
            //used to evaluate the previously set bools and add the 2nd subfolder depending on available dubs/subs
            //if no choice can be made, a fallback folder is used for manual processing
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

            //add a trailing directory separator char, since the folders in shokoserver are currently forcibly set up with one as well
            location += Path.DirectorySeparatorChar;

            //check if any of the available folders matches the constructed path in location, set it as destination
            var dest = args.AvailableFolders.FirstOrDefault(a => a.Location == location);
            
            //DestinationPath is the name of the final subfolder containing the episode files. Get it by preferrence
            var subfolder = GetTitleByPref(anime, TitleType.Official, TitleLanguage.German, TitleLanguage.English, TitleLanguage.Romaji).ReplaceInvalidPathCharacters();
            return (dest, subfolder);
        }

        //nothing to do on plugin load
        public void Load()
        {
        }

        //set the name of the plugin. this will show up in settings-server.json
        public string Name => "BaineRenamer";
    }
}
                                                                                                      