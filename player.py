import pygame, os, pixelperfect

from pixelperfect import *
from pygame.locals import *

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
           self.image, self.rect = load_png('player1v3_still.png', colorkey=colorkey, alpha=alpha)
           self.image = pygame.transform.flip(self.image, True, False)
        else:
           self.image, self.rect = load_png('player2v3_still.png', colorkey=colorkey, alpha=alpha)


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
        self.side = side #left or right 
        self.state = "still"
        self.orientation = "attack" # attack or defens
        self.speed = 10
        self.velocity = 8
        self.mass = 2
        self.isJump = 0	
        self.reinit()
        

    def update(self):

        if self.isJump:
           if self.velocity > 0:
              self.force=( 0.5 * self.mass * (self.velocity *self.velocity) )
           else: 
              self.force=-( 0.5 * self.mass * (self.velocity *self.velocity) )

           print self.force

           self.movepos[1] = self.movepos[1] - self.force

           self.velocity = self.velocity -1

           if self.movepos[1] >= 500:
              self.movepos[1] = 500
              self.isJump=0
              self.velocity = 8

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
        self.state = "jump"
        self.isJump = 1

    def attack(self):
        if self.side == "right":
            print self.movepos
            old_rect=self.rect
            self.image, self.rect = load_png('player2v3_attack.png', (0,0,0), -1)
        if self.side == "left":
            print self.movepos
            old_rect=self.rect
            self.image, self.rect = load_png('player1v3_attack.png', (0,0,0), -1)
        self.rect = old_rect



    def moveleft(self):
        self.velocity_x=-10

        if self.side == "left" and self.orientation=="attack":
	        self.image = pygame.transform.flip(self.image, True, False)
		self.orientation = "defens"
        if self.side == "right" and self.orientation=="defens":
	        self.image = pygame.transform.flip(self.image, True, False)
		self.orientation = "attack"

        self.movepos[0] = self.movepos[0] - (self.speed)
        self.state = "moveleft"

    def moveright(self):
        self.velocity_x=10
        if self.side == "left" and self.orientation=="defens":
	        self.image = pygame.transform.flip(self.image, True, False)
		self.orientation = "attack"

        if self.side == "right" and self.orientation=="attack":
	        self.image = pygame.transform.flip(self.image, True, False)
		self.orientation = "defens"

        self.movepos[0] = self.movepos[0] + (self.speed)
        self.state = "moveright"

    def movedown(self):
        self.movepos[1] = self.movepos[1] + (self.speed)
        self.state = "movedown"
