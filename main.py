#!/usr/bin/python

import pygame, pixelperfect,os

from pygame.locals import *
from pixelperfect import *


def load_png(name, colorkey=None, alpha=False):
    """ Load image and return image object"""
    fullname = os.path.join('res', name)
    try:
        image = pygame.image.load(fullname)
    except pygame.error, message:
        print 'Cannot load image:', fullname
        raise SystemExit, message
    if alpha:image = image.convert_alpha()
    else:image=image.convert()
    if colorkey is not None:
        if colorkey is -1:
            colorkey = image.get_at((0,0))
        image.set_colorkey(colorkey, RLEACCEL)
    return image, image.get_rect()



class Player(pygame.sprite.Sprite):
    def __init__(self, side, colorkey=None, alpha=None):
        pygame.sprite.Sprite.__init__(self)
	if side =="left":
           self.image, self.rect = load_png('player1.png', colorkey=colorkey, alpha=alpha)
        else:
           self.image, self.rect = load_png('player2.png', colorkey=colorkey, alpha=alpha)

        if colorkey and alpha:
            self.hitmask=get_colorkey_and_alpha_hitmask(self.image, self.rect,
                                                        colorkey, alpha)
        elif colorkey:
            self.hitmask=get_colorkey_hitmask(self.image, self.rect,
                                              colorkey)
        elif alpha:
            self.hitmask=get_alpha_hitmask(self.image, self.rect,
                                           alpha)
        else:
            self.hitmask=get_full_hitmask(self.image, self.rect)

        self.mask = pygame.mask.from_surface(self.image)
        screen = pygame.display.get_surface()
        self.area = screen.get_rect()
        self.side = side
        self.speed = 10
        self.state = "still"
        self.reinit()

    def update(self):
        newpos = self.rect.move(self.movepos)
        if self.area.contains(newpos):
            self.rect = newpos
        pygame.event.pump()

    def reinit(self):
        self.state = "still"
        self.movepos = [0,0]
        if self.side == "left":
            self.rect.midleft = self.area.midleft
        elif self.side == "right":
            self.rect.midright = self.area.midright

    def moveup(self):
        self.movepos[1] = self.movepos[1] - (self.speed)
        self.state = "moveup"

    def moveleft(self):
        self.movepos[0] = self.movepos[0] - (self.speed)
        self.state = "moveleft"

    def moveright(self):
        self.movepos[0] = self.movepos[0] + (self.speed)
        self.state = "moveright"

    def movedown(self):
        self.movepos[1] = self.movepos[1] + (self.speed)
        self.state = "movedown"


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
#    player1 = Player("left",-1,None)
#    player2 = Player("right",None,True)
    player1 = Player("left",None,False)
    player2 = Player("right", None,False)

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
            print "hit"

        screen.blit(background, player1.rect, player1.rect)
        screen.blit(background, player2.rect, player2.rect)
        playersprites.update()
        playersprites.draw(screen)
#        screen.blit(background, (0, 0))
        pygame.display.flip()


if __name__ == '__main__': main()
