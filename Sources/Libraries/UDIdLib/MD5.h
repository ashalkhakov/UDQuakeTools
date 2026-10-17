/*
===============================================================================

    Calculates a checksum for a block of data
    using the MD5 message-digest algorithm.

===============================================================================
*/

unsigned long MD5_BlockChecksum( const void *data, int length );
int MD5_FileChecksum( const char *path, char digestHex[33] );
