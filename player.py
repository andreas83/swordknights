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
           self.image, self.rect = load_png('player1v2.png', colorkey=colorkey, alpha=alpha)
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
        self.gravity=3;
        self.ground=10
        self.velocity_x=-10
        self.velocity_y=-20
        self.orientation = "attack" # attack or defens
        

    def update(self):

        if self.state=="jump":
           self.velocity_y= self.velocity_y - self.gravity

           if self.movepos[1] - self.velocity_y > self.ground:
              self.movepos[1] = self.movepos[1] + self.velocity_y

           self.movepos[0] = self.movepos[0] + self.velocity_x


        newpos = self.rect.move(self.movepos)
        if self.area.contains(newpos):
            self.rect = newpos
        pygame.event.pump()


    def reinit(self):
        self.state = "still"
        self.movepos = [0,0]
        print self.area.midleft
        if self.side == "left":
            self.rect.midleft = (50, 600)
        elif self.side == "right":
            self.rect.midright = self.area.midright


    def moveup(self):
        self.state = "jump"

    def attack(self):
        if self.side == "right":
                print self.movepos
                old_rect=self.rect
                self.image, self.rect = load_png('player2_attack.png', (0,0,0), -1)
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
