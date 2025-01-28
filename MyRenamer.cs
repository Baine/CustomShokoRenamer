using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using NLog;
using Shoko.Plugin.Abstractions;
using Shoko.Plugin.Abstractions.Attributes;
using Shoko.Plugin.Abstractions.DataModels;
using Shoko.Plugin.Abstractions.DataModels.Shoko;
using Shoko.Plugin.Abstractions.Events;

namespace Renamer.Baine;

/// <summary>
///     Baines custom Renamer
///     Target Folder Structure is based on available dub/sub languages, as well as being restricted to being >18+
/// </summary>
[RenamerID("BaineRenamer")]
public class MyRenamer : IRenamer
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    //set the name of the plugin. this will show up in settings-server.json
    public string Name => "BaineRenamer";

    public string Description => "Baines Renamer";

    public bool SupportsMoving => true;

    public bool SupportsRenaming => true;


    /// <summary>
    ///     Get the new path for a specified file.
    ///     The target path depends on age restriction and available dubs/subs
    /// </summary>
    /// <param name="args">Arguments for the process, contains FileInfo and more</param>
    public RelocationResult GetNewPath(RelocationEventArgs args)
    {
        RelocationResult result = new();

        //get the anime the file in question is linked to
        var anime = args.Series[0];

        Logger.Info($"Anime Name: {anime.PreferredTitle}");

        //check if the anime in question is restricted to 18+
        var isPorn = anime.Restricted;
        //get the FileInfo of the file in question
        var video = args.File;

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
            textStreamsFile = video.Video.MediaInfo?.TextStreams;

            //dub streams as provided by mediainfo
            audioStreamsFile = video.Video.MediaInfo?.AudioStreams;

            //sub languages as provided by anidb
            textLanguagesAniDb = video.Video.AniDB?.MediaInfo.SubLanguages;

            //sub languages as provided by anidb
            audioLanguagesAniDb = video.Video.AniDB?.MediaInfo.AudioLanguages;
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

        //add a trailing directory separator char, since the folders in shokoserver are currently forcibly set up with one as well
        location += Path.DirectorySeparatorChar;

        //check if any of the available folders matches the constructed path in location, set it as destination
        result.DestinationImportFolder = args.AvailableFolders.FirstOrDefault(a => a.Path == location);

        //DestinationPath is the name of the final subfolder containing the episode files. Get it by preference
        result.Path = GetTitleByPref(anime, true).ReplaceInvalidPathCharacters();

        result.FileName = GetFilename(args);

        return result;
    }

    /// <summary>
    ///     Get anime title as specified by preference. Order matters. if nothing found, preferred title is returned
    /// </summary>
    /// <param name="anime">IAnime object representing the Anime the title has to be searched for</param>
    /// <param name="withAid">include AniDB ID in returned string or not</param>
    /// <returns>string representing the Anime Title for the first language a title is found for</returns>
    private static string GetTitleByPref(IShokoSeries anime, bool withAid)
    {
        //no title found for the preferred languages, return the preferred title as defined by shoko
        return withAid ? anime.PreferredTitle + " {anidb2-" + anime.AnidbAnimeID + "}" : anime.PreferredTitle;
    }

    /// <summary>
    ///     Get Episode Name/Title as specified by preference. if nothing found, the first available is returned
    /// </summary>
    /// <param name="episode">IEpisode object representing the episode to search the name for</param>
    /// <returns>string representing the episode name for the first language a name is found for</returns>
    private static string GetEpNameByPref(IShokoEpisode episode)
    {
        return episode.PreferredTitle;
    }

    /// <summary>
    ///     Get the new filename for a specified file
    /// </summary>
    /// <param name="args">Renaming Arguments, e.g. available folders</param>
    private static string GetFilename(RelocationEventArgs args)
    {
        //make args.FileInfo easier accessible. this refers to the actual file
        var video = args.File;

        //make the anime the episode belongs to easier accessible.
        var anime = args.Series.First();

        // Get the preferred title (Overriden, as shown in Desktop)
        var animeName = anime.PreferredTitle;

        Logger.Info($"Anime Name: {animeName}");

        //make the episode in question easier accessible. this refers to the episode the file is linked to
        var episodes = args.Episodes.ToList();

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
                        paddedEpisodeNumber.Append("E");
                        paddedEpisodeNumber.Append(ep.EpisodeNumber.PadZeroes(anime.EpisodeCounts.Episodes));
                        break;
                    case EpisodeType.Credits:
                        paddedEpisodeNumber.Append("C");
                        paddedEpisodeNumber.Append(ep.EpisodeNumber.PadZeroes(anime.EpisodeCounts.Credits));
                        break;
                    case EpisodeType.Special:
                        paddedEpisodeNumber.Append("S");
                        paddedEpisodeNumber.Append(ep.EpisodeNumber.PadZeroes(anime.EpisodeCounts.Specials));
                        break;
                    case EpisodeType.Trailer:
                        paddedEpisodeNumber.Append("T");
                        paddedEpisodeNumber.Append(ep.EpisodeNumber.PadZeroes(anime.EpisodeCounts.Trailers));
                        break;
                    case EpisodeType.Parody:
                        paddedEpisodeNumber.Append("P");
                        paddedEpisodeNumber.Append(ep.EpisodeNumber.PadZeroes(anime.EpisodeCounts.Parodies));
                        break;
                    case EpisodeType.Other:
                        paddedEpisodeNumber.Append("O");
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