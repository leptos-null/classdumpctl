//
//  ansi-color.h
//  classdumpctl
//
//  Created by Leptos on 8/24/24.
//  Copyright © 2024 Leptos. All rights reserved.
//

#ifndef ANSI_COLOR_h
#define ANSI_COLOR_h

/* ANSI color escapes:
 *   "\033[Em"
 *   where E is the encoding, and the rest are literals, for example:
 *     if 'E' -> "0;30" the full string is "\033[0;30m"
 *   E -> "0" for reset
 *
 *   E -> "T;MC"
 *     T values:
 *       0 for regular
 *       1 for bold
 *       2 for faint
 *       3 for italic
 *       4 for underline
 *     M values:
 *        3 for foreground normal
 *        4 for background normal
 *        9 for foreground bright
 *       10 for background bright
 *     C values:
 *       0 for black
 *       1 for red
 *       2 for green
 *       3 for yellow
 *       4 for blue
 *       5 for purple
 *       6 for cyan
 *       7 for white
 */

#define ANSI_GRAPHIC_RENDITION(e) "\033[" e "m"
#define ANSI_GRAPHIC_RESET_CODE "0"
#define ANSI_GRAPHIC_COLOR(t, m, c) ANSI_GRAPHIC_RENDITION(t ";" m c)

#define ANSI_GRAPHIC_COLOR_TYPE_REGULAR   "0"
#define ANSI_GRAPHIC_COLOR_TYPE_BOLD      "1"
#define ANSI_GRAPHIC_COLOR_TYPE_FAINT     "2"
#define ANSI_GRAPHIC_COLOR_TYPE_ITALIC    "3"
#define ANSI_GRAPHIC_COLOR_TYPE_UNDERLINE "4"

#define ANSI_GRAPHIC_COLOR_ATTRIBUTE_FOREGROUND_NORMAL "3"
#define ANSI_GRAPHIC_COLOR_ATTRIBUTE_BACKGROUND_NORMAL "4"
#define ANSI_GRAPHIC_COLOR_ATTRIBUTE_FOREGROUND_BRIGHT "9"
#define ANSI_GRAPHIC_COLOR_ATTRIBUTE_BACKGROUND_BRIGHT "10"

#define ANSI_GRAPHIC_COLOR_CODE_BLACK  "0"
#define ANSI_GRAPHIC_COLOR_CODE_RED    "1"
#define ANSI_GRAPHIC_COLOR_CODE_GREEN  "2"
#define ANSI_GRAPHIC_COLOR_CODE_YELLOW "3"
#define ANSI_GRAPHIC_COLOR_CODE_BLUE   "4"
#define ANSI_GRAPHIC_COLOR_CODE_PURPLE "5"
#define ANSI_GRAPHIC_COLOR_CODE_CYAN   "6"
#define ANSI_GRAPHIC_COLOR_CODE_WHITE  "7"


#endif /* ANSI_COLOR_h */
