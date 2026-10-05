<?php

namespace CPS\Tools\Library;

/**
 * Locates the release root (the directory holding .commit_hash and .admin-scripts), which is the
 * parent of system/ for normal sites and the parent of ee/ for sites with EE in a subfolder.
 */
class ReleaseRoot
{
    /**
     * @return string Absolute path with a trailing slash.
     */
    public static function path(): string
    {
        $root = dirname(rtrim(SYSPATH, '/')) . '/';
        return basename(rtrim($root, '/')) === 'ee' ? dirname(rtrim($root, '/')) . '/' : $root;
    }

    /**
     * Relative paths resolve against the release root (the process cwd differs under artisan).
     *
     * @param string $path
     * @return string
     */
    public static function resolve(string $path): string
    {
        if ($path === '' || $path[0] === '/') {
            return $path;
        }
        return self::path() . $path;
    }
}
