"""username for login

Revision ID: e41b7c2a9d10
Revises: a205ca73c608
Create Date: 2026-10-15 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = 'e41b7c2a9d10'
down_revision: Union[str, Sequence[str], None] = 'a205ca73c608'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('username', sa.Text(), nullable=True))
    op.create_index('ux_users_username_lower', 'users', [sa.text('lower(username)')], unique=True)


def downgrade() -> None:
    op.drop_index('ux_users_username_lower', table_name='users')
    op.drop_column('users', 'username')
