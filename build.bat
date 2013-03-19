@echo off

if '%1'=='/?' goto help
if '%1'=='-help' goto help
if '%1'=='help' goto help
if '%1'=='-h' goto help

cd %~dp0

.nuget\nuget.exe install .nuget\packages.config -OutputDirectory "packages"

.nuget\nuget.exe pack "Edamame.nuspec"
