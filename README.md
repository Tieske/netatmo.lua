# netatmo.lua
Lua interface to the [Netatmo API](https://dev.netatmo.com/).
Please checkout [the documentation](https://tieske.github.io/netatmo.lua/index.html) for
instructions.


## Status

Early development, session management works.

## Usage

The NetAtmo api requires an OAuth2 flow to acquire access and refresh token.
Use the included docker image to get those.

    docker build --tag=netatmo-auth .
    docker run --rm -it -e "CLIENT_ID=xxx" -e "CLIENT_SECRET=xxx" netatmo-auth

## License & Copyright

See [LICENSE](https://github.com/Tieske/netatmo.lua/blob/master/LICENSE)


### TODO:

- add more methods
- maybe: add a higher level Lua interface with object based access
- maybe: timer based automatic updates with event/callbacks on changes


## History

### Release instructions:

* update changelog below
* make sure to update the version number in `netatmo/init.lua` twice;
  * Doc comments at module level
  * the `_VERSION` constant
* add a rockspec for the new version
* render the docs using `ldoc`
* commit, tag, and push

### unreleased

* breaking: rewite of auth mechanism since password access is no longer supported

### Version 0.1.0, released 22-Oct-2022

* initial release
