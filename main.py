#!/usr/bin/python

import pygame, pixelperfect, player, time

from pygame.locals import *
from pixelperfect import *
from player import *



def main():
    # Initialise screen
    pygame.init()
    screen = pygame.display.set_mode((1250, 850))
    pygame.display.set_caption('Swordknight')

    # Fill background
    background = pygame.Surface(screen.get_size())
    background = background.convert()
    background.fill((255,0,0))

    # Initialise players
    global player1
    global player2

    player1 = Player("left",(0,0,0),False)
    player2 = Player("right", (0,0,0),False)

    playersprites = pygame.sprite.RenderPlain((player1, player2))

    # We need Muke
#    pygame.mixer.music.load('res/music/8bit.mp3')
#    pygame.mixer.music.play(-1, 0.0)

    # Blit everything to the screen
    screen.blit(background, (0, 0))
    pygame.display.flip()

    # Initialise clock
    clock = pygame.time.Clock()

    # Event loop
    while 1:
        clock.tick(60)
        for event in pygame.event.get():
            if event.type == QUIT:
                return
            elif event.type == KEYDOWN:
                if event.key == K_w:
                    player1.moveup()
                if event.key == K_s:
                    player1.movedown()
                if event.key == K_a:
                    player1.moveleft()
                if event.key == K_d:
                    player1.moveright()
                if event.key == K_UP:
                    player2.moveup()
                if event.key == K_LEFT:
                    player2.moveleft()
                if event.key == K_RIGHT:
                    player2.moveright()
                if event.key == K_DOWN:
                    player2.movedown()
                if event.key == 27:
                    return

            elif event.type == KEYUP:
                if event.key == K_a or event.key == K_s or event.key == K_d or event.key == K_w:
                    player1.movepos = [0,0]
                    player1.state = "still"
                if event.key == K_UP or event.key == K_DOWN or event.key == K_LEFT or event.key == K_RIGHT:
                    player2.movepos = [0,0]
                    player2.state = "still"

        if check_collision(player1, player2):
            print  int(round(time.time() * 1000))

        screen.blit(background, player1.rect, player1.rect)
        screen.blit(background, player2.rect, player2.rect)
        playersprites.update()
        playersprites.draw(screen)
#        screen.blit(background, (0, 0))
        pygame.display.flip()


if __name__ == '__main__': main()
