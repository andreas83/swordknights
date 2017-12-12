#!/usr/bin/python

import pygame, os
from pygame.locals import *
	
def load_png(name):
    """ Load image and return image object"""
    fullname = os.path.join('res', name)
    try:
        image = pygame.image.load(fullname)
        if image.get_alpha is None:
            image = image.convert()
        else:
            image = image.convert_alpha()
    except pygame.error, message:
        print 'Cannot load image:', fullname
        raise SystemExit, message
    return image, image.get_rect()

class Player(pygame.sprite.Sprite):
    def __init__(self, side):
        pygame.sprite.Sprite.__init__(self)
	if side =="left":
           self.image, self.rect = load_png('player1.png')
        else:
           self.image, self.rect = load_png('player2.png')

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
    player1 = Player("left")
    player2 = Player("right")

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
        screen.blit(background, player1.rect, player1.rect)
        screen.blit(background, player2.rect, player2.rect)
        playersprites.update()
        playersprites.draw(screen)
#        screen.blit(background, (0, 0))
        pygame.display.flip()


if __name__ == '__main__': main()
