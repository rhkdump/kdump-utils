# Makefile for source rpm: kexec-tools
# $Id$
NAME := kexec-tools
SPECFILE = $(firstword $(wildcard *.spec))

include ../common/Makefile.common
