#
# codesign dylib
#

# replace CODE_SIGNING_IDENTITY with your own`s(in Build Settings -> Code Signing -> Code Signing Identity)
###
CODE_SIGNING_IDENTITY="iPhone Developer: 明溢 多 (P4FGPZ7Y6K)"
###

export CODESIGN_ALLOCATE="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/codesign_allocate"
export PATH="/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin:/Applications/Xcode.app/Contents/Developer/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# dylib path
DYLIB_LOCATION=$1
codesign --verbose --force --sign "$CODE_SIGNING_IDENTITY" "$DYLIB_LOCATION"