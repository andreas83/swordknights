#!/usr/bin/python

import pygame, pixelperfect, player, time

from pygame.locals import *
from pixelperfect import *
from player import *


size = [1300, 800]

def text_to_screen(screen, text, x, y, size = 50,
            color = (200, 000, 000), font_type = 'res/fonts/Capture_it_2.ttf'):
    try:

        text = str(text)
        font = pygame.font.Font(font_type, size)
        text = font.render(text, True, color)
        screen.blit(text, (x, y))

    except Exception, e:
        print 'Font Error, saw it coming'
        raise e

class Ground (pygame.sprite.Sprite):
    def __init__(self, screen):
        color = (255,255,255)
        pygame.sprite.Sprite.__init__(self)
        self.image = pygame.Surface((size[0], size[0]))
        rect = pygame.Rect(20, 20, 20, 3)
        pygame.draw.rect(self.image, color, rect, 1)
        self.image.fill((color))
        self.rect = self.image.get_rect()
        self.rect.center = (size[0] / 2 , size[1]+550 )

def main():
    # Initialise screen
    pygame.init()
    screen = pygame.display.set_mode((size[0], size[1]))
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
    groundsprite = Ground(screen)
    # We need Muke
#    pygame.mixer.music.load('res/music/8bit.mp3')
#    pygame.mixer.music.play(-1, 0.0)

    # Blit everything to the screen
    screen.blit(background, (0, 0))
    pygame.display.flip()

    # Initialise clock
    clock = pygame.time.Clock()

    allSprites = pygame.sprite.Group(playersprites, groundsprite)


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
            screen.blit(background, (0, 0))
            if player1.state == "still" and player2.state == "moveleft" or  player2.state == "moveright":
                text_to_screen(screen, "player 2 won!", size[0]/3, size[1]-600 );
            if player2.state == "still" and player1.state == "moveleft" or  player1.state == "moveright":
                text_to_screen(screen, "player 1 won!", size[0]/3, size[1]-600 );
            player1.reinit();
            player2.reinit();



        screen.blit(background, player1.rect, player1.rect)
        screen.blit(background, player2.rect, player2.rect)
        #playersprites.update()
        #playersprites.draw(screen)


        allSprites.clear(screen, background)
        allSprites.update()
        allSprites.draw(screen)

#        screen.blit(background, (0, 0))
        pygame.display.flip()


if __name__ == '__main__': main()
