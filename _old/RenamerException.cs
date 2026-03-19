using System;

namespace Shoko.Plugin.Renamer
{
    public class RenamerException : Exception
    {
        public RenamerException(string message) : base(message)
        {
        }

        public RenamerException(string message, Exception innerException) : base(message, innerException)
        {
        }
    }
}
