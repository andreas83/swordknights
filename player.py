import pygame, os, pixelperfect

from pixelperfect import *
from pygame.locals import *

# Player properties
PLAYER_ACC = 0.5
PLAYER_FRICTION = -0.12
PLAYER_GRAV = 0.8
size = [1300, 800]
vec = pygame.math.Vector2

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
        self.vel = vec(0, 0)
        self.acc = vec(0, 0)
        self.pos = vec(size[0] / 2, size[1] / 2)


    def update(self):
        self.acc = vec(0, PLAYER_GRAV)
        keys = pygame.key.get_pressed()
        if keys[pygame.K_LEFT]:
            self.acc.x = -PLAYER_ACC
        if keys[pygame.K_RIGHT]:
            self.acc.x = PLAYER_ACC

        # apply friction
        self.acc.x += self.vel.x * PLAYER_FRICTION
        # equations of motion
        self.vel += self.acc
        self.pos += self.vel + 0.5 * self.acc
        # wrap around the sides of the screen
        if self.pos.x > size[0]:
            self.pos.x = 0
        if self.pos.x < 0:
            self.pos.x = size[0]

        self.rect.midbottom = self.pos


    def reinit(self):
        self.state = "still"
        self.movepos = [0,0]
        if self.side == "left":
            self.rect.midleft = self.area.midleft
        elif self.side == "right":
            self.rect.midright = self.area.midright

    def jump(self):
        # jump only if standing on a platform
        self.rect.x += 1
        hits = pygame.sprite.spritecollide(self, self.game.platforms, False)
        self.rect.x -= 1
        if hits:
            self.vel.y = -20

    def moveleft(self):
        self.movepos[0] = self.movepos[0] - (self.speed)
        self.state = "moveleft"

    def moveright(self):
        self.movepos[0] = self.movepos[0] + (self.speed)
        self.state = "moveright"

    def movedown(self):
        self.movepos[1] = self.movepos[1] + (self.speed)
        self.state = "movedown"
